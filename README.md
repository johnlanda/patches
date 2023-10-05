# Patches

![](patches.gif)

Patches is a shell script to help quickly find which patch versions a particular PR made it out in. 

Patches will only work for PRs that were automatically backported by the backport assistant. If there are no tags returned
for a specific PR and you believe that it has gone out, double check to see if it was manually backported.

## Usage

`./patches.sh`

The script will prompt you to install necessary dependencies and login to github. Then it will ask for a repository and a PR
number. It will go and find the automatic backports and their commits then search for tags which contain the relevant commits.