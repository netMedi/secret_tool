# secret_tool

The tool to contextually handle environment variables and secrets in a secure way.


## Requirements

Hard:
  - dash / ash / bash - command shell
  - [1password-cli](https://developer.1password.com/docs/cli/get-started/) - SECRETS' handling
  - bun - building the binary (make sure to **read the log output** after you install Bun, an additional step may be needed for zsh)

Soft:
  - [dotenvx](https://dotenvx.com/docs/install) (!!! dotenvx has several installation methods, be sure to perform an Npm **global install** !!!) - commands' wrapper
  - git - updates

References:
  - [Using 1password with netMedi projects](https://github.com/netMedi/Holvikaari/wiki/Secrets-handling-with-1password#installation-and-setup-of-the-1password-cli-op)


## First time [install]

- clone this project's repo
- cd into this project's root dir
- `./secret_utils.sh install`


## CI install

Declare install_secret_tool block at the top level of `.circleci/config.yml`
```sh
commands:
  # other commands...
  install_secret_tool: &install_secret_tool
    steps:
      - run:
          name: Install secret_tool
          command: |
            if [ -z "$(command -v secret_tool)" ]; then
              npm install -g bun

              VERSION=$(curl -sL https://api.github.com/repos/netMedi/secret_tool/releases/latest | jq -r ".tag_name")
              # replace the above line with
              #   VERSION=main # for a rolling release
              #   VERSION=v2.2.0 # for a chosen tagged release (replace version number)

              export SKIP_OP_USE=1
              rm -rf /tmp/secret_tool 2> /dev/null || true
              git clone git@github.com:netMedi/secret_tool.git /tmp/secret_tool
              cd /tmp/secret_tool
              git checkout $VERSION
              bun install --production --frozen-lockfile 2> /dev/null || true
              ./secret_utils.sh install
              cd ~

              rm -rf /tmp/secret_tool
            fi

            secret_tool --version
```

Whenever you need `secret_tool` installed in the context, include it as a step:
```yml
  steps:
    # other steps
    - install_secret_tool
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
  VERSION=v2.2.0 secret_tool --update
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

Configmap keys are usually lower_case while flat env variables are all UPPER_CASE.

Mixing those or writing in an inappropriate case is not critical and will only affect human-readability of a secret map.

Nesting is either done in yaml manner (by literal nesting) or using double underscore (`__`) delimiter.

```yaml
---
tool_version: 2.2.0
profiles:
  my_C00L_profile:
    --format: yml # optional output format; envfile by default, yml or json
    some_typical_configmap:
      conf1:
        - val1
        - val2
        - val3
    USUAL_ENV__VAR_VAL: asdf

# ^ a totally valid map including a mixture of input formats
```

If profile name contains slashes (`/`), it will be treated as output file path.

### Where to place secret profiles

Profiles for common use shall be placed into the `secret_map.yml` itself.

Custom profiles for personal use can be placed wherever, but will be automagically loaded from `./secret_map.yml.d/` directory at the same level in the project. Alternatively you can refer to them by SECRET_MAP env variable: space separated list of files or masks (example command: `SECRET_MAP='~/my_maps/*.yml ~/Downloads/shared_map_from_teammate.yml' secret_tool --all`).

```sh
mikko@macbook-a2442:~/netMedi/secret_tool$ tree -L 2 ~/netMedi/Holvikaari | grep '\.yml'
# <output trimmed>
├── secret_map.yml
├── secret_map.yml.d
│   ├── my_random_profile1.yml
│   └── my_random_profile2.yml
mikko@macbooka2442:~/netMedi/secret_tool$
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

secret_tool supports three output formats: `envfile` (default), `yml` and `json`. Those can be specified via a `FORMAT` env variable. Can be abbreviated down to one letter. Can be defined in a secret_map profile via `--format` attribute.

Examples:
```sh
  # extract secrets into a JSON file (.env.dev.json)
  FORMAT=json secret_tool dev

  # extract secrets into a YAML file (./config/super_mega_test.yml)
  FILE_NAME_BASE=./config/super_mega_ FORMAT=yml secret_tool test
```

[!] Make sure to end `FILE_NAME_BASE` with a slash (`/`), if you want it to be a directory.
[!] FORMAT is discarded if profile contains `--format` root level property (can be 'yml', 'json' or 'envfile').

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

Example:
```sh
MY_VAR='!!' secret_tool dev # forcefully write empty value for MY_VAR
```


## Last time [uninstall]

- cd into this project's root dir
- `./secret_utils.sh uninstall`
- remove this project's repo


## Creating your own secret_map / integration for new projects

- go to target project's root dir and create `secret_map.yml` (you can use [tests/secret_map.yml](./tests/secret_map.yml) as a starting point)
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

[!] Recommended VS Code extensions: `oven.bun-vscode`.

You can run secret_tool without compiling it. Use `bun src_run` or `./secret_utils.sh src_run`.
To start utils you can have two options: `bun utils` and `./secret_utils.sh`.

After making changes verify shell scripts with shellcheck (`./.posix_verify.sh`) and TypeScript with linter (eslint).
