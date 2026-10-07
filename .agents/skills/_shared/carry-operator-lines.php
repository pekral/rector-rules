#!/usr/bin/env php
<?php

declare(strict_types = 1);

/**
 * Carry the lines the operator added to an agent comment into its next version.
 *
 * Agents and the operator post under one account, so authorship cannot tell an
 * operator line from an agent line. Every version this script builds therefore
 * records a fingerprint of the lines the agent wrote. When the helper rewrites the
 * comment, a line of the previous version whose fingerprint is unknown was added by
 * a person, and it is carried into the new version verbatim.
 *
 * Usage: carry-operator-lines.php <markdown|adf> <namespace> <new-body-file> [<previous-body-file>]
 *
 * - markdown: both files hold GitHub Markdown; the unit is one line, and the
 *   fingerprint is a hidden `<!-- <namespace>:lines=... -->` line.
 * - adf: the new file holds an ADF document, the previous file holds the JSON of
 *   the previous comment body; the unit is one top-level ADF node, and the
 *   fingerprint is appended as ` lines=...` to the visible `<namespace>:actor=` marker.
 *
 * stdout: the new body with the carried units and the fingerprint.
 * stderr: `carried_lines=<n>`, then `carried: <text>` per carried unit. A previous
 * version without a fingerprint carries nothing and says so with `reason=no-fingerprint`.
 */
function carryFingerprint(string $text): string
{
    return substr(hash('sha256', carryNormalize($text)), 0, 8);
}

function carryNormalize(string $text): string
{
    return trim((string) preg_replace('/\s+/u', ' ', $text));
}

/**
 * @param array<mixed> $node
 */
function carryAdfText(array $node): string
{
    $text = is_string($node['text'] ?? null) ? $node['text'] : '';

    if (($node['type'] ?? null) === 'mention' && is_array($node['attrs'] ?? null)) {
        $text .= '@' . (is_string($node['attrs']['id'] ?? null) ? $node['attrs']['id'] : '');
    }

    foreach (is_array($node['content'] ?? null) ? $node['content'] : [] as $child) {
        if (is_array($child)) {
            $text .= carryAdfText($child);
        }
    }

    return $text;
}

/**
 * @param list<string> $carried
 */
function carryReport(array $carried, ?string $reason = null): void
{
    fwrite(STDERR, 'carried_lines=' . count($carried) . ($reason === null ? '' : ' reason=' . $reason) . "\n");

    foreach ($carried as $text) {
        fwrite(STDERR, 'carried: ' . $text . "\n");
    }
}

/**
 * Pick the units of the previous version the agent did not write.
 *
 * @param list<array{text: string, unit: mixed}> $previousUnits
 * @param list<string> $knownFingerprints fingerprints the previous version recorded
 * @param list<string> $newTexts normalized texts of the new version, never carried twice
 * @return list<array{text: string, unit: mixed}>
 */
function carrySelect(array $previousUnits, array $knownFingerprints, array $newTexts): array
{
    $selected = [];
    $seen = $newTexts;

    foreach ($previousUnits as $unit) {
        $normalized = carryNormalize($unit['text']);

        if (in_array(carryFingerprint($unit['text']), $knownFingerprints, strict: true) || in_array($normalized, $seen, strict: true)) {
            continue;
        }

        $seen[] = $normalized;
        $selected[] = $unit;
    }

    return $selected;
}

/**
 * @return list<string>|null
 */
function carryParseFingerprints(string $pattern, string $text): ?array
{
    if (preg_match($pattern, $text, $match) !== 1) {
        return null;
    }

    return $match[1] === '' ? [] : explode(',', $match[1]);
}

function carryMarkdown(string $namespace, string $newBody, ?string $previousBody): string
{
    $quoted = preg_quote($namespace, '/');
    $isMarker = static fn (string $line): bool => preg_match('/^\s*<!-- ' . $quoted . ':(actor|lines)=/', $line) === 1;
    $actorMarkers = [];
    $agentLines = [];

    foreach (explode("\n", $newBody) as $line) {
        if (preg_match('/^\s*<!-- ' . $quoted . ':actor=/', $line) === 1) {
            $actorMarkers[] = trim($line);
        } elseif (!$isMarker($line)) {
            $agentLines[] = rtrim($line);
        }
    }

    $agentTexts = array_values(array_filter(array_map(carryNormalize(...), $agentLines), static fn (string $text): bool => $text !== ''));
    $carried = [];

    if ($previousBody !== null) {
        $known = carryParseFingerprints('/^\s*<!-- ' . $quoted . ':lines=([0-9a-f,]*) -->\s*$/m', $previousBody);
        $previousUnits = [];

        foreach (explode("\n", $previousBody) as $line) {
            if (carryNormalize($line) !== '' && !$isMarker($line)) {
                $previousUnits[] = ['text' => rtrim($line), 'unit' => rtrim($line)];
            }
        }

        if ($known === null) {
            carryReport([], 'no-fingerprint');
        } else {
            $carried = array_map(static fn (array $unit): string => (string) $unit['unit'], carrySelect($previousUnits, $known, $agentTexts));
            carryReport($carried);
        }
    }

    $body = rtrim(implode("\n", $agentLines));

    if ($carried !== []) {
        $body .= "\n\n" . implode("\n\n", $carried);
    }

    $body .= "\n\n<!-- " . $namespace . ':lines=' . implode(',', array_map(carryFingerprint(...), $agentTexts)) . ' -->';

    foreach ($actorMarkers as $marker) {
        $body .= "\n" . $marker;
    }

    return $body;
}

/**
 * @param array<mixed> $node
 */
function carryAppendToMarker(array &$node, string $needle, string $suffix): bool
{
    if (is_string($node['text'] ?? null) && str_contains($node['text'], $needle)) {
        $node['text'] = (string) preg_replace('/ lines=[0-9a-f,]*/', '', $node['text']) . $suffix;

        return true;
    }

    if (!is_array($node['content'] ?? null)) {
        return false;
    }

    for ($index = count($node['content']) - 1; $index >= 0; $index--) {
        if (is_array($node['content'][$index]) && carryAppendToMarker($node['content'][$index], $needle, $suffix)) {
            return true;
        }
    }

    return false;
}

/**
 * @param array<mixed> $document
 * @return array<mixed>
 */
function carryAdf(string $namespace, array $document, mixed $previousBody): array
{
    $needle = $namespace . ':actor=';
    $content = is_array($document['content'] ?? null) ? array_values($document['content']) : [];
    $markerIndex = null;
    $agentTexts = [];

    foreach ($content as $index => $node) {
        $text = is_array($node) ? carryAdfText($node) : '';

        if (str_contains($text, $needle)) {
            $markerIndex = $index;
        } elseif (carryNormalize($text) !== '') {
            $agentTexts[] = carryNormalize($text);
        }
    }

    $carried = [];

    if ($previousBody !== null) {
        $previousContent = is_array($previousBody) && is_array($previousBody['content'] ?? null) ? $previousBody['content'] : null;

        if ($previousContent === null) {
            carryReport([], 'previous-body-not-adf');
        } else {
            $known = null;
            $previousUnits = [];

            foreach ($previousContent as $node) {
                $text = is_array($node) ? carryAdfText($node) : '';

                if (str_contains($text, $needle)) {
                    $known = carryParseFingerprints('/ lines=([0-9a-f,]*)/', $text);
                } elseif (carryNormalize($text) !== '') {
                    $previousUnits[] = ['text' => $text, 'unit' => $node];
                }
            }

            if ($known === null) {
                carryReport([], 'no-fingerprint');
            } else {
                $selected = carrySelect($previousUnits, $known, $agentTexts);
                $carried = array_map(static fn (array $unit): mixed => $unit['unit'], $selected);
                carryReport(array_map(static fn (array $unit): string => carryNormalize($unit['text']), $selected));
            }
        }
    }

    $suffix = ' lines=' . implode(',', array_map(carryFingerprint(...), $agentTexts));

    if ($markerIndex === null) {
        $content = [...$content, ...$carried, ['type' => 'paragraph', 'content' => [['type' => 'text', 'text' => $namespace . ':' . ltrim($suffix)]]]];
    } else {
        $marker = $content[$markerIndex];

        if (is_array($marker)) {
            carryAppendToMarker($marker, $needle, $suffix);
        }

        array_splice($content, $markerIndex, 1, [...$carried, $marker]);
    }

    $document['content'] = $content;

    return $document;
}

if ($argc < 4 || $argc > 5 || !in_array($argv[1], ['markdown', 'adf'], strict: true) || preg_match('/^[a-z][a-z0-9-]*$/', $argv[2]) !== 1) {
    fwrite(STDERR, "Usage: carry-operator-lines.php <markdown|adf> <namespace> <new-body-file> [<previous-body-file>]\n");
    exit(1);
}

$newBody = file_get_contents($argv[3]);
$previousBody = $argc === 5 ? file_get_contents($argv[4]) : null;

if ($newBody === false || $previousBody === false) {
    fwrite(STDERR, "carry-operator-lines.php: cannot read a body file\n");
    exit(1);
}

if ($argv[1] === 'markdown') {
    echo carryMarkdown($argv[2], $newBody, $previousBody);
    exit(0);
}

try {
    $document = json_decode($newBody, true, flags: JSON_THROW_ON_ERROR);
    $previous = $previousBody === null ? null : json_decode($previousBody, true, flags: JSON_THROW_ON_ERROR);
} catch (JsonException $exception) {
    fwrite(STDERR, 'carry-operator-lines.php: invalid JSON: ' . $exception->getMessage() . "\n");
    exit(1);
}

if (!is_array($document)) {
    fwrite(STDERR, "carry-operator-lines.php: the new body is not an ADF document\n");
    exit(1);
}

echo json_encode(carryAdf($argv[2], $document, $previous), JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
