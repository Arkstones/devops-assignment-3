# DevOps Assignment 3 - CI/CD with GitHub Actions

**Author:** Robert Olwoch

[![CI](https://github.com/Arkstones/devops-assignment-3/actions/workflows/ci.yml/badge.svg)](https://github.com/Arkstones/devops-assignment-3/actions/workflows/ci.yml)

A small Bash diagnostic app with a CI pipeline. Every push and pull request is linted, tested, and built into a Docker image that gets smoke-tested. There is no deployment step.

## Project structure

```
assignment-3/
├── README.md
├── app/
│   └── app.sh              # the application
├── scripts/
│   ├── lint.sh             # required files + bash -n + ShellCheck
│   └── build.sh            # docker build + smoke tests
├── tests/
│   └── test.sh             # 21 tests for app.sh
├── .github/
│   └── workflows/
│       └── ci.yml          # validate -> test -> docker
├── Dockerfile
├── compose.yaml
├── .dockerignore
└── grade.sh                # grader supplied with the assignment
```

## Setup

Needs Linux with Bash, plus Docker for the image steps. ShellCheck is optional locally: lint skips it if it isn't installed.

```bash
git clone https://github.com/Arkstones/devops-assignment-3.git
cd devops-assignment-3
chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh
```

## Usage

```bash
./app/app.sh help
./app/app.sh system-info
./app/app.sh check-host github.com
./app/app.sh check-port github.com 443
```

| Command | What it does |
|---|---|
| `system-info` | Hostname, user, date/time, OS, kernel, architecture, uptime, CPU cores and memory |
| `check-host <host>` | Resolves the host and prints its IP addresses |
| `check-port <host> <port>` | Validates the port (1-65535) and tries a TCP connection with a 3 second timeout |
| `help` | Shows usage |

### Exit codes

| Code | Meaning | Examples |
|---|---|---|
| 0 | Success | `help`, `system-info`, host resolves, port is open |
| 1 | Runtime failure | host does not resolve, port is closed |
| 2 | Invalid command or input | no command, unknown command, missing host/port, bad characters in the host, port that is not a number or not in 1-65535, extra arguments |

### With Docker

```bash
docker build -t devops-tool .
docker run --rm devops-tool help
docker run --rm devops-tool system-info
docker run --rm devops-tool check-port github.com 443
```

### With Docker Compose

```bash
docker compose build
docker compose run --rm devops-tool system-info
```

## Running the checks locally

These are the same commands the CI pipeline runs:

```bash
./scripts/lint.sh      # validate
./tests/test.sh        # test
./scripts/build.sh     # docker
./grade.sh             # grader supplied with the assignment
```

### What the tests cover

`tests/test.sh` has 21 tests:

- **help:** `help` and `--help`
- **system-info:** output, kernel line, and extra arguments rejected
- **Invalid commands:** missing command and invalid command
- **check-host:** missing host, `localhost`, an IP address, bad characters, a name starting with `-`, and an unknown host. The unknown host uses the reserved `.invalid` domain, so it fails the same way everywhere.
- **check-port:**
  - Invalid input: missing port, non-numeric, `0`, `65536`, negative, and a bad host
  - A closed port, which returns 1
  - An open port, which returns 0 against a small local `python3` server the test starts and stops itself

The tests only use `localhost` and `.invalid`, so they don't depend on internet access.

## CI pipeline

`.github/workflows/ci.yml` runs on every `push` and `pull_request`:

```
validate  ->  test  ->  docker
```

| Job | Runs | Depends on |
|---|---|---|
| `validate` | `scripts/lint.sh` (ShellCheck is installed if the runner does not have it) | - |
| `test` | `tests/test.sh` | `needs: validate` |
| `docker` | `scripts/build.sh` (build + smoke tests, including an invalid command) | `needs: test` |

Because of `needs:`, a failing job stops everything after it. If lint fails, the tests and the Docker build are skipped. The workflow only has `contents: read` permission because it never writes to the repo.

## CI failure demonstration

To show the pipeline catching a mistake, I used the `ci-failure-demo` branch:

1. **Broken commit:** added a new test to `tests/test.sh` but left a quote unclosed. The `validate` job failed at the `bash -n` syntax check, and `test` and `docker` were skipped because of `needs:`.
2. **Fix commit:** closed the quote. All three jobs passed.
3. The branch was merged into `main` through a pull request, which also ran the pipeline and passed.

The failed and passing runs can be seen in the [Actions tab](https://github.com/Arkstones/devops-assignment-3/actions) by filtering on the `ci-failure-demo` branch.

## Docker design

- **Base image:** `alpine:3.20`, pinned. Only `bash` is installed (`apk add --no-cache`); everything else comes with Alpine's busybox.
- **What gets copied:** only `app/app.sh`, with `chmod 755`. `.dockerignore` keeps `.git`, `.github`, tests, scripts and docs out of the build context.
- **User:** runs as a normal user (`appuser`), not root. `build.sh` checks this.
- **Entrypoint:** `ENTRYPOINT ["/app/app.sh"]` with `CMD ["help"]`, so `docker run devops-tool <command>` passes the command straight to the app.
- **Compose:** the service is read-only, with `no-new-privileges`.

## Git workflow

- `feature/app`: app and tests, merged into `main`.
- `feature/ci`: lint, build, Docker and the workflow, merged into `main`.
- `ci-failure-demo`: the CI failure demonstration above, merged with a pull request.

Merges use `--no-ff` so each branch shows in the history.

## Assumptions

- `check-host` only resolves the host and doesn't ping it, because GitHub-hosted runners block ping (ICMP) and the pipeline must give the same result every time.
- Hostnames may only contain letters, numbers, `.`, `-` and `:` (IPv6), so input can't inject shell commands.
- `check-port` treats "connection refused" and "timed out after 3 seconds" the same way: closed or not reachable, exit 1.
