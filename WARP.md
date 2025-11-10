# Warp Terminal Integration

This project supports enhanced developer workflows with [Warp](https://www.warp.dev/), the modern terminal built for teams.

## Features

- Fast command execution with GPU acceleration
- Built-in AI command search
- Collaborative workflows
- Rich output formatting

## Getting Started

1. Install Warp from https://www.warp.dev/
2. Open this project directory in Warp
3. Use built-in commands like `/build`, `/test`, `/sim` for iOS development
4. Leverage Warp AI for command suggestions

## Custom Commands

This project includes custom slash commands (see `.claude/commands/`) that work seamlessly in Warp:
- `/build` - Quick build validation
- `/test` - Run Swift tests
- `/sim` - Launch in iOS Simulator
- `/device-deploy` - Deploy to connected device
- `/deploy-backend` - Deploy Cloudflare Workers
- `/logs` - Stream backend logs

See [MCP_SETUP.md](MCP_SETUP.md) for full command documentation.
