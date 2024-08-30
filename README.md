# secret_tool

The tool to contextually handle environment variables and secrets in a secure way.


## Requirements

Hard:
  - dash / ash / bash - command shell
  - [yq](https://github.com/mikefarah/yq) - YAML secret map's handling
  - [1password-cli](https://developer.1password.com/docs/cli/get-started/) - SECRETS' handling
  - node / bun

Soft:
  - [dotenvx](https://dotenvx.com/docs/install) (!!! dotenvx has several installation methods, be sure to perform an Npm global install !!!) - commands' wrapper
  - git - updates

References:
  - [Using 1password with netmedi projects](https://github.com/netMedi/Holvikaari/wiki/Secrets-handling-with-1password#installation-and-setup-of-the-1password-cli-op)


## First time [install]

- clone this project's repo
- cd into this project's root dir
- `./secret_utils.sh install`


## CI install

Declare update_secret_tool block at the top level of `.circleci/config.yml`
```sh
update_secret_tool: &update_secret_tool
  name: Update Secret Tool
  command: |
    tagged_version=$(curl -sL https://api.github.com/repos/netMedi/secret_tool/releases/latest | jq -r ".tag_name")
    # change tagged_version value to exact tag, if needed; example: v1.4.4
    sudo wget -qO /usr/local/bin/secret_tool https://raw.githubusercontent.com/netMedi/secret_tool/$tagged_version/secret_tool.sh
    sudo chmod +x /usr/local/bin/secret_tool
    secret_tool --version
```

Whenever you need `secret_tool` installed in the context, include it as a step:
```yml
  steps:
    # other steps
    - run: *update_secret_tool
```


## Update

There are a couple of automated ways to update secret_tool.

1. The latest revision of main:

```sh
  # latest revision of main branch
  secret_tool --update
```

2. Exact tag:

```sh
  # install exact release tag of main branch
  VERSION=v1.4.4 secret_tool --update
```

3. The latest tag (stable)
```sh
  # install the latest tagged release (stable)
  VERSION=latest secret_tool --update

  # or
  VERSION=stable secret_tool --update
```


## Running with up-to-date secrets

- go to target project
- perform `secret_tool <profile_name(s)>` to produce .env.* file(s):

```sh
secret_tool my_profile_name another_profile

# or

EXTRACT='my_profile_name another_profile' secret_tool
```


## Input format (naming and conventions)

Secret map can either be written as a configmap or a flat envfile (or a mix of those).

Configmap keys are usually lower_case while envfile is all UPPER_CASE.

Mixing those or writing in an inappropriate case is not critical and will only affect human-readability of a secret map.

Nesting is either done in yaml manner or using double underscore (`__`) delimiter.

```yaml
---
profiles:
  my_C00L_profile:
    some_typical_configmap:
      conf1:
        - val1
        - val2
        - val3
    USUAL_ENV__VAR_VAL: asdf

# ^ a totally valid map including a mixture of input formats
```

### Inline arrays

If you need to declare an array you have a few options:

1. Use YAML arrays:
```yaml
my_array:
  - one
  - two
  - three
```

2. Use JSON array notation for YAML:
```yaml
my_array: ['one', 'two', 'three']
```

3. Use a comma-separated string variable (parse later in the code):
(this one is useful if code will work with raw value of env variable)
```yaml
my_arrayish_string: 'one,two,three'
```

4. [Special cases] array of quoted values
(this one is used, for example, in `postgres` container image environment: `POSTGRES_MULTIPLE_DATABASES`)
```yaml
my_special_string: '"quoted value 1","quoted value 2","quoted value 3"'
```


## Ouput format (machine- or human-readable)

secret_tool supports three output formats: `envfile` (default), `yml` and `json`. Those can be specified via a `FORMAT` env variable.

Examples:
```sh
  # extract secrets into a JSON file (.env.dev.json)
  FORMAT=json secret_tool dev

  # extract secrets into a YAML file (./config/super_mega_test.yml)
  FILE_NAME_BASE=./config/super_mega_ FORMAT=yml secret_tool test
```

Format is case-insensitive. YAML can be written either as `YML` or `YAML`.

By default any existing output file with the same name will get renamed into file postfixed with `.YYYY-MM-DD_hh-mm-ss.bak`. This sort of backup can be skipped by setting `LIVE_DANGEROUSLY=1`.

## Local overrides

If you need to apply values other than the ones secret_map provides, you have a few options:

1. Edit output file directly.
2. Set variables as shell defaults in your .bashrc / .zshrc / .zprofile etc.
3. Export variable for the current terminal session (ex: `export MY_CUSTOM_VAR=123`)
4. Set variable value inline prior to the command (ex: `MY_CUSTOM_VAR=123 secret_tool dev`)

[!] Option 1 allows you to set the value as clear text only.

[!] Options 2-4, however, allow you to make 1password references into use (ex: `MY_CUSTOM_VAR=':::op://Employee/MY_OVERRIDES/custom' secret_tool dev`) and that value will be dynamically evaluated at assignment. To discard some of the values set by secret_map, you can use literals for empty string, array and object: `!!` (discard whatever value present in secret_map), `!![]` (set value to empty array) and `!!{}` (set value to empty object).

<!--

## Express set command

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

-->


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

### [!] Avoid using dots `[.]` in profile names. You can use alphanum characters `[A-z0-9]`, dash `[-]` and underscore `[_]`.

Profiles starting with double-dash are considered internal templates and therefore are not displayed for `secret_tool --profiles`.


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



## Modifying secret_tool scripts

After making changes verify all the scripts with shellcheck: `./.posix_verify.sh`
