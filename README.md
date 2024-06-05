# secret_tool

The tool to contextually handle environment variables and secrets in a secure way.


## Requirements

Hard:
  - bash
  - yq
  - 1password (for handling SECRETS)
  - 1password-cli (for handling SECRETS)

Soft:
  - dotenvx (for wrapping commands and self-test)
  - git (for updates)


## First time [install]

- clone this project's repo
- cd into this project's root dir
- `./secret_utils.sh install`


## Running with up-to-date secrets

- go to target project
- perform `secret_tool <profile_name(s)>` to produce .env.* file(s)


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
