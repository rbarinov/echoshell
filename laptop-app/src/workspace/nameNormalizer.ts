/**
 * Normalizes names to kebab-case format with Latin characters only.
 * Handles transliteration from Cyrillic and other scripts.
 * 
 * Examples:
 * - "My Workspace" -> "my-workspace"
 * - "Акме Корп" -> "akme-korp"
 * - "feature_auth" -> "feature-auth"
 * - "MyProject123" -> "myproject123"
 */

// Cyrillic to Latin transliteration map
const CYRILLIC_TO_LATIN: Record<string, string> = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
  'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
  'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D', 'Е': 'E', 'Ё': 'Yo',
  'Ж': 'Zh', 'З': 'Z', 'И': 'I', 'Й': 'Y', 'К': 'K', 'Л': 'L', 'М': 'M',
  'Н': 'N', 'О': 'O', 'П': 'P', 'Р': 'R', 'С': 'S', 'Т': 'T', 'У': 'U',
  'Ф': 'F', 'Х': 'H', 'Ц': 'Ts', 'Ч': 'Ch', 'Ш': 'Sh', 'Щ': 'Shch',
  'Ъ': '', 'Ы': 'Y', 'Ь': '', 'Э': 'E', 'Ю': 'Yu', 'Я': 'Ya'
};

/**
 * Transliterates Cyrillic characters to Latin
 */
function transliterate(text: string): string {
  return text.split('').map(char => {
    return CYRILLIC_TO_LATIN[char] || char;
  }).join('');
}

/**
 * Normalizes a name to kebab-case format with Latin characters only.
 * 
 * Process:
 * 1. Transliterate Cyrillic to Latin
 * 2. Convert to lowercase
 * 3. Replace spaces, underscores, and multiple hyphens with single hyphen
 * 4. Remove all non-alphanumeric characters except hyphens
 * 5. Remove leading/trailing hyphens
 * 6. Collapse multiple consecutive hyphens into one
 * 
 * @param name - The name to normalize
 * @returns Normalized name in kebab-case
 */
export function normalizeToKebabCase(name: string): string {
  if (!name || typeof name !== 'string') {
    return '';
  }

  // Step 1: Transliterate Cyrillic to Latin
  let normalized = transliterate(name.trim());

  // Step 2: Convert to lowercase
  normalized = normalized.toLowerCase();

  // Step 3: Replace spaces, underscores, and other separators with hyphens
  normalized = normalized.replace(/[\s_]+/g, '-');

  // Step 4: Remove all non-alphanumeric characters except hyphens
  normalized = normalized.replace(/[^a-z0-9-]/g, '');

  // Step 5: Collapse multiple consecutive hyphens into one
  normalized = normalized.replace(/-+/g, '-');

  // Step 6: Remove leading and trailing hyphens
  normalized = normalized.replace(/^-+|-+$/g, '');

  // Ensure we have at least one character
  if (normalized.length === 0) {
    // Fallback: use a default name based on timestamp
    normalized = `item-${Date.now()}`;
  }

  return normalized;
}

/**
 * Normalizes workspace name to kebab-case
 */
export function normalizeWorkspaceName(name: string): string {
  return normalizeToKebabCase(name);
}

/**
 * Normalizes repository name to kebab-case
 */
export function normalizeRepositoryName(name: string): string {
  return normalizeToKebabCase(name);
}

/**
 * Normalizes branch or feature name to kebab-case
 */
export function normalizeBranchName(name: string): string {
  return normalizeToKebabCase(name);
}

/**
 * Normalizes worktree name to kebab-case
 */
export function normalizeWorktreeName(name: string): string {
  return normalizeToKebabCase(name);
}

/**
 * Normalizes terminal name to kebab-case
 */
export function normalizeTerminalName(name: string): string {
  return normalizeToKebabCase(name);
}

