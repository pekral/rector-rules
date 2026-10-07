#!/usr/bin/env php
<?php

declare(strict_types = 1);

/**
 * Convert the JIRA Wiki Markup subset used by AI Olympus reports into ADF.
 *
 * @return list<array<string, mixed>>
 */
function jiraWikiInlineNodes(string $text): array
{
    $nodes = [];
    $offset = 0;
    // Strong and emphasis never open or close inside a word, the same as in JIRA, so an identifier
    // like `campaign_report_stats` or `2*3*4` stays literal text. A code span inside them may carry
    // the delimiter, e.g. `_metric {{total_user_open}}_`.
    $pattern = '/\[~accountid:(?<mentionId>[A-Za-z0-9:_-]+)\]|\{\{(?<codeText>.+?)\}\}|\[(?<linkText>[^|\]]+)\|(?<href>[^\]]+)\]|(?<![\p{L}\p{N}])\*(?<strongText>(?:\{\{.+?\}\}|[^*])+)\*(?![\p{L}\p{N}])|(?<![\p{L}\p{N}])_(?<emText>(?:\{\{.+?\}\}|[^_])+)_(?![\p{L}\p{N}])/u';

    while (preg_match($pattern, $text, $match, PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL, $offset) === 1) {
        $position = $match[0][1];
        jiraWikiAppendTextNode($nodes, substr($text, $offset, $position - $offset));

        if ($match['mentionId'][1] >= 0) {
            // A mention notifies the account, so it becomes an ADF mention node, never plain text.
            $nodes[] = ['type' => 'mention', 'attrs' => ['id' => $match['mentionId'][0]]];
        } elseif ($match['codeText'][1] >= 0) {
            // Code spans are literal in JIRA, so their content is never re-parsed.
            jiraWikiAppendTextNode($nodes, $match['codeText'][0], [['type' => 'code']]);
        } elseif ($match['linkText'][1] >= 0) {
            jiraWikiAppendMarkedNodes($nodes, $match['linkText'][0], [
                'type' => 'link',
                'attrs' => ['href' => $match['href'][0]],
            ]);
        } elseif ($match['strongText'][1] >= 0) {
            jiraWikiAppendMarkedNodes($nodes, $match['strongText'][0], ['type' => 'strong']);
        } else {
            jiraWikiAppendMarkedNodes($nodes, $match['emText'][0], ['type' => 'em']);
        }

        $offset = $position + strlen($match[0][0]);
    }

    jiraWikiAppendTextNode($nodes, substr($text, $offset));

    return $nodes;
}

/**
 * Re-parse the span so nested markup — `{{code}}` inside `*bold*`, emphasis inside a link label —
 * reaches ADF as its own mark instead of leaking into the rendered comment as literal Wiki Markup.
 *
 * @param list<array<string, mixed>> $nodes
 * @param array<string, mixed> $mark
 */
function jiraWikiAppendMarkedNodes(array &$nodes, string $text, array $mark): void
{
    foreach (jiraWikiInlineNodes($text) as $node) {
        /** @var list<array<string, mixed>> $marks */
        $marks = $node['marks'] ?? [];

        // ADF allows the code mark beside a link only: JIRA rejects a code + strong or code + em span,
        // so inline code inside bold or italic text keeps its code mark alone.
        if ($mark['type'] === 'link' || !in_array(['type' => 'code'], $marks, true)) {
            $marks[] = $mark;
        }

        $node['marks'] = $marks;
        $nodes[] = $node;
    }
}

/**
 * @param list<array<string, mixed>> $nodes
 * @param list<array<string, mixed>> $marks
 */
function jiraWikiAppendTextNode(array &$nodes, string $text, array $marks = []): void
{
    if ($text === '') {
        return;
    }

    $node = ['type' => 'text', 'text' => $text];

    if ($marks !== []) {
        $node['marks'] = $marks;
    }

    $nodes[] = $node;
}

/**
 * @return array{version: int, type: string, content: list<array<string, mixed>>}
 */
function jiraWikiMarkupToAdf(string $wikiMarkup): array
{
    $lines = preg_split('/\R/u', $wikiMarkup);

    if (!is_array($lines)) {
        $lines = [$wikiMarkup];
    }

    $content = [];

    for ($index = 0, $lineCount = count($lines); $index < $lineCount; $index++) {
        $line = $lines[$index];

        if (trim($line) === '') {
            continue;
        }

        if (preg_match('/^h([1-6])\.\s+(.+)$/u', $line, $heading) === 1) {
            $content[] = [
                'type' => 'heading',
                'attrs' => ['level' => (int) $heading[1]],
                'content' => jiraWikiInlineNodes($heading[2]),
            ];

            continue;
        }

        if (preg_match('/^\{code(?::([^}]+))?\}$/u', $line, $codeStart) === 1) {
            $code = [];

            while (++$index < $lineCount && $lines[$index] !== '{code}') {
                $code[] = $lines[$index];
            }

            $node = [
                'type' => 'codeBlock',
                'content' => [['type' => 'text', 'text' => implode("\n", $code)]],
            ];

            if (($codeStart[1] ?? '') !== '') {
                $node['attrs'] = ['language' => $codeStart[1]];
            }

            $content[] = $node;

            continue;
        }

        if (preg_match('/^\{quote\}(.*)\{quote\}$/u', $line, $quote) === 1) {
            $content[] = jiraWikiQuoteNode($quote[1]);

            continue;
        }

        if ($line === '{quote}') {
            $quote = [];

            while (++$index < $lineCount && $lines[$index] !== '{quote}') {
                $quote[] = $lines[$index];
            }

            $content[] = jiraWikiQuoteNode(implode("\n", $quote));

            continue;
        }

        // `*` and `-` both open a bullet list in JIRA Wiki Markup; `#` opens a numbered one.
        if (preg_match('/^([*#-])\s+(.+)$/u', $line, $listItem) === 1) {
            $marker = $listItem[1];
            $items = [];

            do {
                $items[] = [
                    'type' => 'listItem',
                    'content' => [[
                        'type' => 'paragraph',
                        'content' => jiraWikiInlineNodes($listItem[2]),
                    ]],
                ];
                $nextIndex = $index + 1;

                if ($nextIndex >= $lineCount
                    || preg_match('/^' . preg_quote($marker, '/') . '\s+(.+)$/u', $lines[$nextIndex], $nextItem) !== 1
                ) {
                    break;
                }

                $index = $nextIndex;
                $listItem[2] = $nextItem[1];
            } while (true);

            $content[] = [
                'type' => $marker === '#' ? 'orderedList' : 'bulletList',
                'content' => $items,
            ];

            continue;
        }

        if ($line === '----') {
            $content[] = ['type' => 'rule'];

            continue;
        }

        $content[] = [
            'type' => 'paragraph',
            'content' => jiraWikiInlineNodes($line),
        ];
    }

    return [
        'version' => 1,
        'type' => 'doc',
        'content' => $content,
    ];
}

/**
 * @return array{type: string, content: list<array<string, mixed>>}
 */
function jiraWikiQuoteNode(string $text): array
{
    return [
        'type' => 'blockquote',
        'content' => [[
            'type' => 'paragraph',
            'content' => jiraWikiInlineNodes($text),
        ]],
    ];
}

$wikiMarkup = file_get_contents('php://stdin');

if (!is_string($wikiMarkup)) {
    fwrite(STDERR, "wiki-markup-to-adf.php: failed to read stdin\n");
    exit(1);
}

// A body cut mid-character (a byte-based truncation of Czech text) still publishes: the broken
// bytes become U+FFFD instead of failing the whole comment.
try {
    echo json_encode(
        jiraWikiMarkupToAdf($wikiMarkup),
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR,
    );
    echo "\n";
} catch (JsonException $exception) {
    fwrite(STDERR, 'wiki-markup-to-adf.php: ' . $exception->getMessage() . "\n");
    exit(1);
}
