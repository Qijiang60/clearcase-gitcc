#Git-clearcase
It is a simple bridge between base ClearCase and Git. Like [charleso](https://github.com/charleso/git-cc) I wrote this to calm my
nerves while using ClearCase and Git. Almost everything is held by two additional git commands `git ccpush` and `git ccpull`

    +-------+  ccpush  +-----------+
    |       | -------> |           |
    |  Git  |  ccfetch | ClearCase |
    |       | <------- |           |
    +-------+          +-----------+

##Disclamer
This module is preliminary. It works under certain conditions only. I currently use it
on Cygwin with ClearCase 7. Feel free to report any issues, suggestions or comments.

##Installation

    git clone https://github.com/nowox/ClearCase-Gitcc
    cd ClearCase-Gitcc-master
    perl Makefile.PL
    make install

##Usage
Gitcc is made to be used with ClearCase non UCM with a ClearCase view ready to work with. 

You will first need a Git repository. If nothing exists you can create one anywhere on your local drive. The only requirement is that the directory name that hold the Git repository must have the same name as your ClearCase working directory. For instance if I would like to work in `/cygdrive/l/myview/myvob/.../foo`, your working directory has to be named `foo`. 

So let's do it: 

    mkdir foo && cd foo
    git init
    git config --local clearcase.remote "/cygdrive/l/myview/myvob/.../foo"
    
The last command will link your local Git repository with ClearCase. 

You might want to add some ignored files to your `.gitignore`:

    echo "**/*.keep"      >> .gitignore
    echo "**/*.contrib"   >> .gitignore
    echo "**/*.keep.*"    >> .gitignore
    echo "**/*.contrib.*" >> .gitignore
    
Notice that you can also mask files and folders that you want to let untouched on ClearCase.

From this it is now possible to retrieve the ClearCase view

    git ccpull --verbose
    git commit -m "Initial ClearCase import"
    
Laster when you want to push your changes on ClearCase, you can use the other command:

    git commit -m "A comment that will be used on ClearCase as well"
    git ccpush --checkin --verbose
    
Note that if you are afraid to checkin your files on ClearCase, you can omit the `--checkin` option

To see the differences with ClearCase, simply use this command. It always work with the working copies on both sides

    git ccdiff --stat
    git ccdiff --name-only
    git ccdiff foo.c
    
##Workflow

The suggested workflow start with a cc branch which is the local mirror to your ClearCase repository. When merging with this branch, you always favor the --no-fs option to avoid any fast forward merge.

    git checkout -b cc
    git ccfetch
    git commit -m "Imported from ClearCase"
    git checkout master
    git merge --no-ff cc

-

     o---o (master)
      \ /
       o (cc)
      /
    ccfetch

From this you will work on your master and eventually use other branches:

              o---o (test)
             /     \
    o---o---o--o----o--o (master)
     \ /
      o (cc)
     /      
    ccfetch

A some point, you want to synchronize your local copy with the ClearCase version.

    git checkout cc
    git ccfetch
    git commit -m "Imported from ClearCase"
    git checkout master
    git merge --no-ff cc

-

              o---o (test)
             /     \
    o---o---o--o----o--o--o (master)
     \ /                 /
      o-----------------o (cc)    
     /                 /
    ccfetch         ccfetch

It is now time to push your changes on ClearCase. This operation should be as short as possible since you don't want to let others checkin their changes:

    git checkout cc
    git ccfetch
    git commit -m "Imported Changes "
    git merge --no-ff master
    git ccfetch --checkin

-

              o---o (test)
             /     \
    o---o---o--o----o--o--o (master)
     \ /                 / \
      o-----------------o-o-o (cc)
     /                 / /   \
    ccfetch          ccfetch   ccpush   

##Thanks
I would like to thanks VonC from StackOverflow that helped me to find my way with ClearCase, especially on this workflow [question](http://stackoverflow.com/questions/28280685/toward-an-ideal-workflow-with-clearcase-and-git).
