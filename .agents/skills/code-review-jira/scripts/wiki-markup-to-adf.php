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
    $pattern = '/\{\{(?<codeText>.+?)\}\}|\[(?<linkText>[^|\]]+)\|(?<href>[^\]]+)\]|\*(?<strongText>[^*]+)\*|_(?<emText>[^_]+)_/u';

    while (preg_match($pattern, $text, $match, PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL, $offset) === 1) {
        $position = $match[0][1];
        jiraWikiAppendTextNode($nodes, substr($text, $offset, $position - $offset));

        if ($match['codeText'][1] >= 0) {
            jiraWikiAppendTextNode($nodes, $match['codeText'][0], [['type' => 'code']]);
        } elseif ($match['linkText'][1] >= 0) {
            jiraWikiAppendTextNode($nodes, $match['linkText'][0], [[
                'type' => 'link',
                'attrs' => ['href' => $match['href'][0]],
            ]]);
        } elseif ($match['strongText'][1] >= 0) {
            jiraWikiAppendTextNode($nodes, $match['strongText'][0], [['type' => 'strong']]);
        } else {
            jiraWikiAppendTextNode($nodes, $match['emText'][0], [['type' => 'em']]);
        }

        $offset = $position + strlen($match[0][0]);
    }

    jiraWikiAppendTextNode($nodes, substr($text, $offset));

    return $nodes;
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

        if (preg_match('/^([*#])\s+(.+)$/u', $line, $listItem) === 1) {
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
                'type' => $marker === '*' ? 'bulletList' : 'orderedList',
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

try {
    echo json_encode(
        jiraWikiMarkupToAdf($wikiMarkup),
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR,
    );
    echo "\n";
} catch (JsonException $exception) {
    fwrite(STDERR, 'wiki-markup-to-adf.php: ' . $exception->getMessage() . "\n");
    exit(1);
}
