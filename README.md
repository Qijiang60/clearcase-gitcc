#Git-clearcase
It is a simple bridge between base ClearCase and Git. Like [charleso][1] I wrote this to calm my
nerves while using ClearCase and Git.

#Warning
This script is very preliminary. It does its job only under certain conditions. I currently use it
on Cygwin with ClearCase 7. Please report any issues or comments.

#Installation

    git clone https://github.com/nowox/ClearCase-Gitcc
    cd ClearCase-Gitcc-master
    perl Makefile.PL
    make install

#Usage
Gitcc is made to be used with ClearCase non UCM. The expected workflow is the following:

##First steps
1. Create a dynamic view on ClearCase
2. Create git repository somewhere

Please note that your Git repository name should have the same name as your ClearCase working
directory *i.e.* `foo`

    mkdir foo
    cd foo
    git init foo
    git config --local clearcase.remote "/cygdrive/l/view/path/foo"

You might want to add some ignored files to your `.gitignore`:

    echo "**/*.keep"    >> .gitignore
    echo "**/*.contrib" >> .gitignore

Notice that you can also mask files and folders that you want to let untouched on ClearCase.

4. Create a branch

I usually use the default `cc` to follow my ClearCase state. Then you can get everything from
ClearCase.

    git checkout -b cc
    git ccpull --verbose
    git commit -m "Imported from ClearCase" .

5. Do your work

Now you can work, modify remove or add files...

    git checkout master
    echo "touched" >> file
    git commit -m "I touched file" .

6. Sync with ClearCase

In order to synchronize your changes with ClearCase you can just do this:

    git checkout cc
    git ccpull
    git commit -m "If changed occured" .

    git merge --no-ff master
    git commit -m "Merge done"

    git ccpush --checkin --verbose

##Additional commands

    git ccdiff --stat
    git ccdiff --name-only
    git ccdiff <file>


[1] https://github.com/charleso/git-cc
