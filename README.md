# Kustomization builds compare

Github action to print the differences of kustomize build files.
Using kustomize cli tool will help you reduce kubernetes yaml definitions that requires differences when deployed to specific environments, 
   but will take away the readability of the end result object definition. 
Using this tool will help you validate and show the changes that are generated.

The script can be used as a local tool. Simply copy the shell script code into a executable file
```
# dependencies: yq, kustomize, csplit

sudo vi /usr/local/bin/kustomize-diff
# paste the data from entrypoint.sh
sudo chmod +x /usr/local/bin/kustomize-diff
```  
Point your terminal to the location where you have the main kustomization.yaml file and execute `kustomize-diff`, or one of the following
```
kustomize-diff /home/user/projects/my-kubernetes-project/overlays master  > full path directory location, compare with local master branch
kustomize-diff overlays origin/master >  relative path, comparing with last branched off hash from remote master
kustomize-diff "" origin/develop > kustomization.yaml in the current directory, comparing with the same location in remote develop branch 
```

## Inputs
### `kustomization-location`
**Required** Project relative path of your kustomization.yaml file. Default is the root of the project `"./"`.
### `compare-branch-name`
**Required** The name of the branch that your current branch is branched of. As this script is fetching the last common commit git hash,
 you need to make sure that such hash exist in your branch.
 
## Outputs
none

## Example usage
Create a github action file in your  project such as `.github/workflows/kustomize-compare.yaml`

```
name: compare

on:
  pull_request:
    branches:
      - master                                                                 <-- trigger validation on pull requests done against master
jobs:
  kustomize-overlay-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2                                              <-- git checkout helper
      - run: git fetch --unshallow origin master && git checkout ${GITHUB_REF} <-- register origin master as branch to compare to, PLUS checkout current branch 
      - name: +++++ KUSTOMIZE DIFF +++++                                       
        uses: loveholidays/gitops-action-kustomize-compare@v1.0                <-- use this public github action
        with:
          kustomization-location: overlays                                     <-- location of the this-project/overlays/kustomization.yaml
          compare-branch-name: origin/master                                   <-- build code from branched off hash, present in origin/master
```

Example on execution
```
  Set up job                                                            2s
  Build loveholidays/gitops-action-kustomize-compare@v1.0              28s
  Run actions/checkout@v2                                               1s
  Run git fetch --unshallow origin master && git checkout ${GITHUB_REF} 3s
  +++++ KUSTOMIZE DIFF +++++                                           10s
  Post actions/checkout@v2                                              0s
  Complete job



 +++++ KUSTOMIZE DIFF +++++

Run loveholidays/gitops-action-kustomize-compare@v1.0
/usr/bin/docker run [...]  "overlays" "origin/master"
  ┌───────
  ├ Comparing kustomize builds overlays kustomization.yaml 
  ├ FROM new HEAD
  ├   TO old origin/master branched off commit [some commit long sha]
  ├ Preparing overlays/kustomize_build_temp/origin/master-detached (identifier master-detached)
  ├ HEAD is now at [some short sha] Merge pull request [some commit message]
  ├─ Previous HEAD position was [some short sha] Merge pull request [some commit message]
  ├─ HEAD is now at [some short sha] [some commit message]
  ├ Splitting kustomization build into separate objects
  └ Processing diff

╭─ + NEW OBJECT
│ apiVersion: v1
│ kind: ConfigMap
│ metadata:
│   name: test-add-new-object
│   namespace: default
╰──────────

╭─ * UPDATED OBJECT 
│ apiVersion: apps/v1
│ kind: Deployment
│ metadata:
│   name: some-name
│   namespace: default
╰─┬─────────
  │ @@ -10,7 +10,7 @@ spec:
  │          resources:
  │            limits:
  │              cpu: 100m
  │ -            memory: 256Mi
  │ +            memory: 300Mi
  │            requests:
  │              cpu: 100m
  │              memory: 256Mi
  ╰──────────

╭─ - DELETED OBJECT
│ apiVersion: v1
│ kind: ConfigMap
│ metadata:
│   name: test-delete-object
│   namespace: default
╰──────────

OR
  ╭─
  │ No changes detected for overlays/kustomization.yaml
  ╰─
```
