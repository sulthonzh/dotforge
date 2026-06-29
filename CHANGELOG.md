# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Removed `eval` from ssh-agent startup (shellcheck SC2086)
- Quoted `STACK_FILE` assignment to prevent word-splitting

### Changed
- Sharpened README hook from generic description to problem-first narrative
- Added comparison table vs ssh-deploy, appleboy/ssh-action, manual SSH scripts
- Pinned Docker Compose to v2.30.3 (latest stable)

### Removed
- Deleted stale `docker-entrypoint.sh.bak` backup file

## [1.1.0] - 2024-08-15

### Added
- Enhanced security with input validation (shell injection + path traversal protection)
- Comprehensive test suite (action.yml validation, Docker build, shell syntax, input validation)
- Non-root user support in Dockerfile
- Control character validation in `validate_input`
- Cleanup trap for SSH keys, agent, and Docker context on exit
- Temporary file for registry password (avoid leaking in process list)
- `.gitignore` with comprehensive patterns

### Changed
- Removed `ssh-keyscan` (dead code — `StrictHostKeyChecking=no` makes it unnecessary)
- Escaped `$file` in cleanup loop for filenames with spaces
- Quoted symlink target and link name in `execute_ssh`
- Added warning when `pull_images_first` is used with `docker-swarm` mode

### Fixed
- Interactive prompt issue with `ssh-add`
- Shell quoting vulnerabilities in `scp` and SSH commands
- `validate_input` missing redirection operators (`<`, `>`)
- Double space in cleanup output

## [1.0.0] - 2024-06-11

### Added
- Initial release with basic Docker deployment functionality
- Support for docker-compose and Docker Swarm deployment modes
- SSH-based remote deployment
- Private registry authentication
- Stack file copy and cleanup
- Docker system prune support
