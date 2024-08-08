# secret_tool

The tool to contextually handle environment variables and secrets in a secure way.


## Requirements

Hard:
  - dash / ash / bash - command shell
  - [yq](https://github.com/mikefarah/yq) - YAML secret map's handling
  - [1password-cli](https://developer.1password.com/docs/cli/get-started/) - SECRETS' handling

Soft:
  - [dotenvx](https://dotenvx.com/docs/install) (!!! dotenvx has several installation methods, be sure to perform an Npm global install !!!) - commands' wrapper
  - git - updates

References:
  - [Using 1password with netmedi projects](https://github.com/netMedi/Holvikaari/wiki/Secrets-handling-with-1password#installation-and-setup-of-the-1password-cli-op)

## First time [install]

- clone this project's repo
- cd into this project's root dir
- `./secret_utils.sh install`


## Running with up-to-date secrets

- go to target project
- perform `secret_tool <profile_name(s)>` to produce .env.* file(s)


## Express dump commands

Sometimes you may need to extract just one secret or append something to environment file that you do not to regenerate as a whole.
That can be done with an express dump feature using ` -- ` (double dash command). You can do it as a single operation or have multiple targets, also can be chained to an existing extraction command. If target file is not present yet, it will be created.

Examples:

```sh
# just one variable to extract
secret_tool -- ./.env.whatever:SOMEVAR=:::op://Shared/demo20240531-secretTool/text

# extract the whole profile and then two more extra variables
secret_tool dev -- ./.env.dev:ANOTHERVAR=:::op://Shared/demo20240531-secretTool/text ./.env.dev:VAR2=sdfsdf
```

[!] Keep in mind that poorly named secret vaults (the ones that have spaces in the ref links) will need to be wrapped in quotation marks:

```sh
secret_tool -- "./.env.whatever:SOMEVAR=:::op://Shared/i am an expert in machine-friendly naming/text"
```

The reason express commands exist is to allow batch extraction in complex scenarios and avoid repetitive 1password auth checks.


## Last time [uninstall]

- cd into this project's root dir
- `./secret_utils.sh uninstall`
- remove this project's repo


## Creating your own secret_map / integration for new projects

- go to target project's root dir and create `secret_map.yml` (you can use [secret_map.sample.yml](./secret_map.sample.yml) as a starting point)
- [gitignore /.env*](.gitignore) to prevent accidental secret file submission to git
- if necessary, include non-gitignored contextual overrides via .env.* files with the same profile names (refer to Katedraali packages for examples)
- rewrite package.json commands with `dotenvx run -f ...` wrapper and make sure to include all relevant profiles that are required for command (example: `"test": "dotenvx run -f ../../.env.test -f .env.test -- jest"` - package-level script would load global defaults and package-level .env files)
- produce .env.* files and check if all required variables are present
- commit your changes to target project


<!--
### PROFILE inheritance

YAML has an inheritance feature built in. You do not have to redeclare the repeating values again if they are already defined in existing profile. For example, if you need to create a close derivative of "dev" profile adding a few extra variables on top, you may inherit existing ones using anchor:

```yaml
# ...

dev: &dev
  var1: 1
  var2: 'b'
  var3: 'c'

dev-extended:
  <<: *dev
  var3: 'new value'
  var4: 'new variable'
```

Notice how profile to derive from is marked with `&dev` and the new profile has `<<: *dev` essentially including existing profile as a template to modify and extend.
-->


## Modifying secret_tool scripts

After making changes verify all the scripts with shellcheck: `./.posix_verify.sh`
