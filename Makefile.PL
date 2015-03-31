#!/usr/bin/env perl
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %parms = (
    NAME            => 'ClearCase::Gitcc',
    AUTHOR          => 'Yves Chevallier <nowox@x0x.ch>',
    VERSION_FROM    => './lib/ClearCase/Gitcc.pm',
    INSTALLSCRIPT   => '/usr/libexec/git-core',
    INST_SCRIPT     => './script',
    PREREQ_PM       => { 'ClearCase::Argv' => '1.54',
                         'Git' => '0.01'
                       },
    dist            => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);

WriteMakefile( %parms );
