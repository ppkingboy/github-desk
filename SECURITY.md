# Security

## Credential storage

GitHub access and refresh tokens are stored in the macOS Keychain. They are never written to project files, repository remotes, command arguments, or application preferences.

## Git transport

Git operations use HTTPS with an ephemeral askpass helper. The access token is passed only through the process environment and is not embedded in the remote URL.

## Secret scanning

Publishing and committing are blocked when high-confidence secret patterns are found, including private keys, GitHub tokens, cloud credentials, and common API keys.

## Reporting

Please report security issues privately through GitHub Security Advisories for this repository.
