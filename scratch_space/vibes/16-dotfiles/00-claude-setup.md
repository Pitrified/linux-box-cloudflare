# claude setup

## main claude instructions

create main claude settings and main instructions

in
/home/pmn/repos/linux-box-cloudflare/configs/repomgr/repos.toml
we have a bunch of repos listed, we want to cross check all the copilot instructions available and distill one central claude instruction set for all the repos
note that while we have a lot of python projects, we also have some flutter/go/godot/js/etc projects.
can we create some general instructions for each language and load them as needed?
and create just the python one for now, but establish the pattern

## per repo claude instructions

the current copilot instructions are readable by claude?
do we need to point to them explicitly in the claude instructions?

## permissions

we can set some permissions for claude to auto run some commands, eg `ls`, `cat`, `git status`, `git diff`, `git log`, `docker ps`, `docker images`, etc
strictly read only, no possible leakage of permissions (eg find exec can then run a `-delete` or something)
leave core safe commands to remove some easy approval, but we want to be very safe
