#!/bin/sh

set -e

##########################################################
# Setup and Installation Steps                           #
##########################################################

# Check that brew is installed
if ! command -v brew >/dev/null 2>&1; then
  # not installed
  read -p "Brew not detected. Install now? (y/n)" -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Check that gum is installed
if ! command -v gum >/dev/null 2>&1; then
  # not installed
  read -p "Gum not detected. Install now? (y/n)" -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi

  brew install gum
fi

# Check that gh cli installed
if ! command -v gh >/dev/null 2>&1; then
  # not installed
  # we can use gum now that it should be installed
  gum confirm "Install gh cli?" && brew install gh
fi

##########################################################
# End Setup and Installation Steps                       #
##########################################################

# Check if gh cli is already authenticated
if ! gh auth status >/dev/null 2>&1; then
  gum confirm "Login to github cli?" && gh auth login
fi

mkdir -p "$HOME/.patches"

# if repo list exists, ask if they want to use or update
# else always grab list
if [ -f "$HOME/.patches/repos.txt" ]
then
  gum confirm "Would you like to refresh the repository list?" \
    && gum spin --spinner dot --title "Fetching list of hashicorp repos..." -- \
      gh repo list hashicorp --limit 2500 --json name --jq '"hashicorp/" + .[].name' > "$HOME/.patches/repos.txt"
else
  # have to grab the repos since we don't have them already
  gum spin --spinner dot --title "Fetching list of hashicorp repos..." -- \
    gh repo list hashicorp --limit 2500 --json name --jq '"hashicorp/" + .[].name' > "$HOME/.patches/repos.txt"
fi
REPO_LIST=$(<"$HOME/.patches/repos.txt")

REPO=$(gh repo list hashicorp --limit 2000 --json name --jq '"hashicorp/" + .[].name' | gum filter)
REPO_URL=$(gh repo view $REPO --json sshUrl --jq '.sshUrl')

PR_NUM=$(gum input --placeholder "<PR_NUM>" --prompt "> #")
JQ_QUERY="[\"$REPO\", \"#\" + (.number|tostring), .mergeCommit.oid, .title] | join(\" \")"
PR_RESULTS=$(gh pr view --repo "$REPO" "$PR_NUM" --json number,mergeCommit,title --jq "$JQ_QUERY")

PR_COMMIT=""

if [ -z "$PR_RESULTS" ]
then
  gum style \
    --foreground 212 --border-foreground 212 --border double \
    --align center --width 50 --margin "1 2" --padding "2 4" \
    'PR not found' "#$PR_NUM" 'Exiting...'
  exit 1
else
  gum confirm "Is this the correct PR? $PR_RESULTS"
  if [ $? -ne 0 ]
  then
    gum style "Exiting..."
    exit 1
  fi

  PR_COMMIT=$(gh pr view --repo "$REPO" "$PR_NUM" --json mergeCommit --jq ".mergeCommit.oid")
  echo "$PR_COMMIT"
fi

# Find all of the backports
BP_PRS=$(gh search prs --repo $REPO --match body "This PR is auto-generated from #$PR_NUM" --json number --jq ".[].number")

# could allow manual input of PR numbers here for manual backport cases

# split prs into array, guard against '*' in string with noglob
set -o noglob
IFS=$'\n' BP_ARR=($BP_PRS); unset IFS
set +o noglob

# Grab the commits for each of the backport PRs
j=0
for BP_PR_NUM in "${BP_ARR[@]}"
do
  echo "Found Backport PR: $BP_PR_NUM"
  MERGE_COMMITS[j]=$(gh pr view --repo "$REPO" "$BP_PR_NUM" --json mergeCommit --jq ".mergeCommit.oid")
  j=$((j+1))
done

# get a treeless clone of the repo
# Check if repo exists
# if so ask if they want to refresh the repo
# else clone it

# bare clone of repo
# need to check if exists already
cd "$HOME/.patches/"
REPO_SHORT=${REPO##*/}
if [ -d "$HOME/.patches/$REPO_SHORT.git" ]
then
  # already cloned, ask if they would like to refresh
  gum confirm "Repository treeless clone exists. Would you like to refresh it?" \
    && rm -rf "$HOME/.patches/$REPO_SHORT.git" \
    && gum spin --show-output --spinner dot --title "Cloning $REPO... (may take a moment)" -- git clone --progress --bare $REPO_URL 2>&1
else
  # We don't have the repo yet so we have to clone it
  gum spin --show-output --spinner dot --title "Cloning $REPO... (may take a moment)" -- git clone --progress --bare $REPO_URL 2>&1
fi

cd "$HOME/.patches/$REPO_SHORT.git"

TAGS=()
# Check the main PR for which tags it is in
MAIN_TAGS=$(git tag --contains $PR_COMMIT)

# split prs into array, guard against '*' in string with noglob
set -o noglob
IFS=$'\n' MAIN_TAGS_ARR=($MAIN_TAGS); unset IFS
set +o noglob

# Check the backport merge commits
for BP_COMMIT in "${MERGE_COMMITS[@]}"
do
  BP_TAGS=$(git tag --contains $BP_COMMIT)

  set -o noglob
  IFS=$'\n' BP_TAGS_ARR=($BP_TAGS); unset IFS
  set +o noglob

  MAIN_TAGS_ARR=("${MAIN_TAGS_ARR[@]}" "${BP_TAGS_ARR[@]}")
done

# sort the tags
set -o noglob
SORTED=(`printf '%s\n' "${MAIN_TAGS_ARR[@]}" | sort`)

printf "\nFound the following tags:\n"
printf "* %s\n"  "${SORTED[@]}" | gum format

if [ ${#SORTED[@]} -eq 0 ]
then
  printf "* No matching tags found. Please check the original PR for manual backports.\n" | gum format
fi
set +o noglob
