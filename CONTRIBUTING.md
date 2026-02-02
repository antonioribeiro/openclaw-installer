# Contributing to OpenClaw Installer

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When creating a bug report, include:

- **Ubuntu version**: e.g., 22.04 LTS, 24.04 LTS
- **Installation method**: Direct VPS, Docker, or curl one-liner
- **Error messages**: Full output from `/var/log/openclaw_install.log`
- **Steps to reproduce**: What you did that led to the issue
- **Expected behavior**: What you expected to happen
- **Actual behavior**: What actually happened

### Suggesting Enhancements

Enhancement suggestions are welcome! Please provide:

- A clear description of the enhancement
- Use cases for the enhancement
- Examples of how it would work

### Pull Requests

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/yourusername/openclaw-installer.git`
3. **Create a branch**: `git checkout -b feature/your-feature-name`
4. **Make changes** and test locally using Docker
5. **Commit** with a clear message
6. **Push** to your fork: `git push origin feature/your-feature-name`
7. **Create a Pull Request**

### Testing Changes

Test your changes using the Docker environment:

```bash
cd docker
make reset    # Start fresh
make install  # Run your modified script
```

### Code Style

- Use **4 spaces** for indentation (no tabs)
- Add comments for complex logic
- Follow the existing function structure
- Keep functions focused and modular

### Script Guidelines

- **Idempotency**: The script should be safe to run multiple times
- **Logging**: All operations should log to `/var/log/openclaw_install.log`
- **Error handling**: Use proper error handling with clear messages
- **User feedback**: Provide color-coded console output for important steps

## Project Structure

```
openclaw-installer/
├── install.sh            # Main installation script
├── docker/               # Docker testing environment
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── Makefile
└── server/               # Direct VPS deployment
    └── Makefile
```

## Areas That Need Help

- Additional Ubuntu version testing
- Documentation improvements
- Additional error handling
- Security hardening
- Performance optimizations

## Getting Help

If you need help contributing:

- Open a discussion on GitHub
- Check existing issues and PRs
- Review the OpenClaw documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
