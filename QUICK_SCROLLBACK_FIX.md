# Quick Fix: Tmux Scrollback History

## Problem
Only visible area shown on iPhone (last ~30 lines)  
Missing scrollback history

## Solution
Capture full tmux scrollback using `tmux capture-pane`

```typescript
// Before: Only our buffer
return session.outputBuffer.join('');

// After: Full tmux history (50,000 lines)
execSync(`tmux capture-pane -t ${tmuxSessionName} -p -S -50000`);
```

## Test It

```bash
# Generate history
seq 1 1000

# On iPhone:
1. Close and reopen terminal
2. Should see ALL 1000 lines ✅
3. Scroll up to line 1 ✅
```

## Restart to Apply

```bash
cd laptop-app
npm run dev:laptop-app
```

Full scrollback history now available! 🎉
