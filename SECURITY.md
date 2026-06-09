# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| v68 (MIAB) | ✅ |
| Older versions | ❌ |

## Reporting a vulnerability

If you find a security vulnerability in the Docker packaging or scripts in this repository, please report it privately.

**Do not** open a public GitHub issue for security vulnerabilities.

Contact: open an issue at [github.com/rasrobo/mail-in-a-docker](https://github.com/rasrobo/mail-in-a-docker) with the label `security`, or if the issue is sensitive, reach out through the repository maintainer's contact information.

For vulnerabilities in Mail-in-a-Box itself, report them to the [upstream MIAB project](https://github.com/mail-in-a-box/mailinabox/security).

## Security considerations

- The container runs with `privileged: true` to manage systemd. Review whether this is acceptable for your threat model.
- Mail-in-a-Box disables UFW during setup. Re-enable firewall rules after installation.
- Keep Docker and the host OS updated.
- The container uses self-signed SSL certificates initially. Let's Encrypt provisioning happens on first MIAB setup.
- All mail services bind to `0.0.0.0` inside the container. Port exposure to the internet is controlled by Docker's port mapping and host firewall.
