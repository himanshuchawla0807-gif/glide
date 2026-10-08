# Security

Please do not post secrets, private browser data or exploitable details in a public issue. Use GitHub's private vulnerability reporting when it is enabled for this repository. Otherwise contact the maintainer through their GitHub profile to arrange a private report.

This project has no hosted backend. Review the companion's permissions, local pairing, origin restriction, frame limits and HTTP/HTTPS validation when making security changes. The local threat model trusts the current macOS user: software already running as that user can access their local files. The transport token is not intended to defend against a fully compromised user account.
