#!/usr/bin/env perl
#Author: Y.Chevallier <nowox@x0x.ch>
#Date:   2015-03-26 Thu 12:46 PM

package Gitcc;

=head1 SYNOPSIS

Gitcc is a tiny package used by git-ccdiff, git-ccpush and git-ccpull. These programs
are made to synchronize Git repositories with ClearCase dynamic views.

=head2 COPYRIGHT

Copyright (c) 2015 by Yves Chevallier.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the “Software”), to deal in the Software without
restriction, including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

The Software is provided “as is”, without warranty of any kind, express or implied,
including but not limited to the warranties of merchantability, fitness for a particular
purpose and noninfringement. In no event shall the authors or copyright holders X be
liable for any claim, damages or other liability, whether in an action of contract, tort
or otherwise, arising from, out of or in connection with the software or the use or other
dealings in the Software.

=cut

#----------------------------------------------------------------------------------------
# Modules
#----------------------------------------------------------------------------------------
use 5.010;
use strict;
use warnings;
use Pod::Usage;
use Getopt::Long qw(:config no_ignore_case bundling);
use ClearCase::Argv  qw(chdir ctsystem ctexec ctqx ctpipe);
use Git;
use File::Basename;
use Cwd 'abs_path';
use File::Compare;
use Term::ANSIColor;
use File::Copy;
use File::Path qw(make_path);
use Array::Utils qw(:all);
use Argv;

my %cfg = (
    comment => '',
    checkin => 0,
    verbose => 0, # 0: quiet, 1: verbose, 2: notice, 3: debug, 4: insane
    force   => 0, # In some case we have warnings, we can force actions to be done.
    hard    => 0, # Some time we need to force harder, we can insist with this option.
    dry_run => 0,
    dog     => 0,
);

ClearCase::Argv->dbglevel( ($cfg{verbose} > 0)? 1 : 0 );

our $VERSION = '0.01';

sub version { $VERSION }

#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------

# Die if not in a git repository
`[ -d .git ] || git rev-parse --git-dir > /dev/null 2>&1`;
error("Not a git repository") if $?;
$cfg{gitdir} = Git::command_oneline('rev-parse', '--show-toplevel');

# Get ClearCase specific configuration
$cfg{ccdir} = `git config --get clearcase.remote` ||
    error("Git config variable 'clearcase.remote' has a null value");
chomp $cfg{ccdir};

# Convert DOS/Windows path to POSIX if required
if ($cfg{ccdir} =~ /^[a-z]:\\/i) {
    $cfg{ccdir} = `cygpath "$cfg{ccdir}"`;
    chomp $cfg{ccdir};
}

# Check if the above destination exists
if (not -d $cfg{ccdir}) {
    # Weak attempt to start the view on the MVFS mount
    local $_ = $cfg{ccdir};
    s>\\>/>g;
    s>^/(view|cygdrive)/\w/>>i;
    s>^\w:/>>;
    error("Destination $cfg{ccdir} does not exist") if m|(\w+)/|;
}

# Create Git and ClearCase objects
my $cc  = ClearCase::Argv->new({autofail=>1, autochomp=>1});
my $git = Git->repository($cfg{gitdir});

# Determine the destination's view name
chdir($cfg{ccdir});
$cfg{ccview} = $cc->argv('pwv -s')->qx ||
    error("Unable to determine the destination view");

# Ensure both ClearCase directory and Git directory have a common basename
my ($basename) = $cfg{gitdir} =~ /(\w+)\/?$/;
if ($cfg{ccview} eq $basename) {
    error ("You cannot work outside from VOB. '$basename' is not located inside a VOB");
}
if (not $cfg{ccdir} =~ /$cfg{ccview}.*$basename\/?$/) {
    error ("No common basename '$basename' found in between '$cfg{ccdir}' and '$cfg{gitdir}'");
}

# Get the last git comment by default
if (not $git->command('status') =~ /Initial commit/ and length $cfg{comment} eq 0) {
    $cfg{comment} = $git->command_oneline('log', '--format=%B', '-n1', 'HEAD')
};

#
# Main data structure. It contains all the needed information on the
# - Git repository
# - ClearCase view
#
my %data = (
    # Null file, this is an example (this hash is flushed later)
    null => {
        status   => '<', # '<' git only, '>' cc only, '=' same on both, '+' modified
        revision => '/main/main-A_BRANCH_NAME/8',
        rule     => '.../main-A_BRANCH_NAME/LATEST',
        symlink  => '# ../../../a/path/foo.c',
    },
);

sub scrutinize {
    my $force = shift;

    # Look on both Git and ClearCase and establish the status for each file.
    %data = ();
    state $done = 0;
    $done = 0 if defined $force and $force eq 1;
    return if $done;

    # Step one: start with git
    notice("Retrieving git-files...");
    $data{$_}{status} = '<' for ($git->command('ls-files'));

    # Step two: get ClearCase files and status
    notice("Retrieving clearcase files...");
    for ($cc->argv('ls -recurse -vob')->qx) {
        s/@@.*$//;  # We only want the filename
        s/\\/\//g;  # All files should use forward slash
        s/^\.\///;  # We do not want file to start with ./
        next if -d; # Do not process directories
        $data{$1}{symlink} = $2 if /^(.*) --> (.*)$/; # Is a symbolic link?
        s/ --> .*$//;

        $data{$_}{status} = ($data{$_}{status} and $data{$_}{status} eq '<')?'?':'>';
    }

    # Remove ignored files from the hash
    removeIgnored(\%data);

    # Each files that exist on both sides are marked '?'. We then identify if they are
    # '=' equal, or if they differ '+'. In some case, the compare can fail with 'x'
    notice("Comparing files...");
    for (keys %data) {
        if ($data{$_}{status} eq '?') {
            debug("Comparing '$_'...");
            $data{$_}{status} = qw{= + x}[compare(gitpath($_), ccpath($_))];
        }
        error("Unable to compare '$_'") if $data{$_}{status} eq 'x';
    }

    # Profit!
    notice("Scanning done.");
    $done = 1;

    # Firewall, we expect that more than 50% of the local files exist on ClearCase
    # in order to avoid to mess up everything if the ClearCase view was not correctly
    # configured.
    my $n = keys %data;
    my $e = grep $data{$_}{status} =~ /[=+x]/, keys %data;
    notice("We've detected that $e files over $n exist on both sides");
    notice("More than ".($e/$n*100)."% of files exists on both sides");
    if ($e / $n < 0.5 and not $cfg{force} and not $cfg{hard}) {
        $cfg{dog} = 1;
    }

    %data;
}

sub removeIgnored {
    my $data = shift;

    notice("Removing ignored files according to .gitignore...");
    chdir $cfg{gitdir};
    my $ccfiles = join ' ', keys $data;
    my @ignored = split('\n', `git check-ignore $ccfiles`);
    chdir $cfg{ccdir};
    warning("Some files on ClearCase are masked by .gitignore:") if @ignored > 0;
    for (@ignored) {
        delete $data->{$_};
        warning(" -$_");
    }
}

sub dog {
    return unless $cfg{dog};
    error("Too many differences detected on ClearCase. Are you sure of your configuration?
        You can still force with --force --hard`");
}

sub check {
    my %params = @_;

    if($params{git_clean} and not git_isclean()) {
        error("Your working directory is not up to date. \nCommit your changes or reset to your HEAD.");
    }
    if($params{cc_clean} and not cc_isclean()) {
        error("ClearCase view has checkouts.\nPlease checkin your files first.\n");
    }
}

sub comment {
    $cfg{comment} = shift;
}

sub verbose {
    $cfg{verbose} = int shift;
}

sub dry_run {
    $cfg{dry_run} = int shift;
}

sub checkin_flag {
    $cfg{checkin} = shift;
}

# ---------------------------------------------------------------------------------------
# Git commands
# ---------------------------------------------------------------------------------------
sub git {
    if($cfg{dry_run}) {
        say 'git ', join(' ', @_);
    } else {
        $git->command(@_);
    }
}

sub git_add {
    git('add', shift);
}

sub git_rm {
    git('rm', shift);
}

sub git_isclean {
    my @result = $git->command('status', '--porcelain');
    use Data::Dumper;
    @result = map(/^[^?]{2}/, @result);
    return not scalar @result;
}

# ---------------------------------------------------------------------------------------
# Shell commands
# ---------------------------------------------------------------------------------------
sub shell {
    my $command = shift;
    if($cfg{dry_run}) {
       say "+$command"
    } else {
       say $command if $cfg{verbose};
       say "Error: unable to execute `$command`" and exit -1 if system($command);
    }
}

sub cp {
    my ($src, $dst) = @_;
    if (not -e $src) {
        error("'$src' does not exist");
    }
    elsif (-d $src) {
        make_path($dst);
    }
    elsif (-f $src) {
        make_path(dirname($dst)) unless -e dirname($dst);

        # Argv is faster than File::Copy
        my $v = ($cfg{verbose} > 0)?'v':'';
        my $exit = Argv->new('cp', '-p'.$v, $src, $dst)->system;
        error("copy failed with exit code $exit") if $exit ne 0; 
    }
    else {
        error("Unknown error");
    }
}

# Copy a file from Git to ClearCase
sub cp2cc {
    my $file = shift;
    my $ccpath = ccpath($file);

    # Here we need to check if the file is a symbolink link. If this is the case,
    # we need to copy it to it's real location
    $ccpath = ccpath($data{$file}{symlink}) if defined $data{$file}{symlink};

    message("Pushing $file");
    cp(gitpath($file), $ccpath);
}

# Copy a file from ClearCase to Git
sub cp2git {
    my $file = shift;
    message("Retrieving $file");
    cp(ccpath($file), gitpath($file));
}

# ---------------------------------------------------------------------------------------
# Clearcase commands
# ---------------------------------------------------------------------------------------
sub cc_checkout {
    dog();
    my $file = ccpath(shift);
    if($cfg{dry_run}) {
        say "Checkout $file";
    } else {
        $cc->co($file)->comment($cfg{comment})->system;
    }
}

sub cc_checkin {
    dog();
    return unless ($cfg{checkin});
    my $file = ccpath(shift);
    if($cfg{dry_run}) {
        say "Checkin $file";
    } else {
        $cc->ci($file)->comment($cfg{comment})->system;
    }
}

sub cc_add {
    dog();
    my $file = shift;
    cc_checkout(dirname($file));
    $cc->mkelem(ccpath($file))->comment($cfg{comment})->system;
    cc_checkin(dirname($file));
}

sub cc_rm {
    dog();
    my $file = shift;
    cc_checkout(dirname($file));
    $cc->rmname(['-f', ccpath($file)])->system;
    cc_checkin(dirname($file));
}

sub cc_isclean {
    my @files = $cc->argv('lsco -cview -short')->qx;
    return ( (@files > 0)? 0 : 1 );
}

# Paths expension
sub ccpath  { ("$cfg{ccdir}/".shift ) =~ s|/+|/|gr }
sub gitpath { ("$cfg{gitdir}/".shift) =~ s|/+|/|gr }

# Warning/Error messages...
sub message { say shift                       }
sub warning { say shift if $cfg{verbose} > 0  }
sub notice  { say shift if $cfg{verbose} > 1  }
sub debug   { say shift if $cfg{verbose} > 2  }
sub error   { say "Error: ".shift and exit -1 }

1;
