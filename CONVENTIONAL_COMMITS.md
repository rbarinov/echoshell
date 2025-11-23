# Conventional Commits Setup

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to ensure consistent and meaningful commit messages.

## Setup

The project is configured with:
- **Commitlint**: Validates commit messages against the Conventional Commits specification
- **Husky**: Git hooks to automatically run commitlint on commit

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Code style changes (formatting, missing semi-colons, etc.)
- `refactor`: Code refactoring without feature changes or bug fixes
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `build`: Changes to build system or external dependencies
- `ci`: Changes to CI configuration files and scripts
- `chore`: Other changes that don't modify src or test files
- `revert`: Reverts a previous commit

### Scope (Optional)

The scope should be the name of the package or component affected:
- `ios`: iOS app changes
- `watchos`: WatchOS app changes
- `laptop-app`: Laptop application changes
- `tunnel-server`: Tunnel server changes
- `api`: API changes
- `terminal`: Terminal management changes
- `docs`: Documentation changes

### Subject

- Use imperative, present tense: "add" not "added" nor "adds"
- Don't capitalize the first letter
- No period (.) at the end
- Maximum 100 characters
- Must be in English

### Body (Optional)

- Provide additional context about the change
- Explain the "what" and "why" vs. "how"
- Reference issue numbers if applicable
- Must be in English

### Footer (Optional)

- Reference related issues: `Fixes #123`, `Closes #456`
- Breaking changes: `BREAKING CHANGE: description`
- Must be in English

## Examples

### Simple commit
```
feat(ios): add QR code scanner for laptop pairing
```

### Commit with scope
```
fix(terminal): resolve WebSocket reconnection issue
```

### Commit with body
```
feat(laptop-app): add ephemeral key distribution

Implement secure key distribution system with 1-hour expiration.
Keys are automatically refreshed when less than 5 minutes remain.

Fixes #42
```

### Breaking change
```
feat(api): redesign terminal session management

BREAKING CHANGE: Session creation now requires explicit working directory parameter.
Old API endpoint /terminal/create is deprecated. Use /terminal/create-v2 instead.
```

### Multiple types
```
fix(ios): resolve audio playback issue

fix(watchos): sync audio state with iPhone app
```

## Validation

Commitlint automatically validates all commit messages. If a commit message doesn't follow the format, the commit will be rejected with an error message.

### Manual Validation

You can manually validate a commit message:
```bash
echo "feat: your commit message" | npx commitlint
```

### Bypassing Validation (Not Recommended)

If you absolutely need to bypass validation (e.g., for merge commits), use:
```bash
git commit --no-verify
```

**Note**: This should only be used in exceptional circumstances and is not recommended for regular commits.

## Language Requirement

**IMPORTANT**: All commit messages MUST be written in English. This is a mandatory project requirement. See `CLAUDE.md` section 0.1 for the complete language policy.
