# Answering a reviewer question

A comment asks a question when it requests information instead of a change, for example *"Why is this not in the repository?"* or *"What happens when the list is empty?"*. Treat such a comment as its own checklist item. Never turn it into a code change the reviewer did not ask for. Answer it under `@rules/code-review/general.md` *Answering a question raised during a review*.

## In the review loop

1. Open the code the question targets on the current head, and run the test or command that settles the question.
2. Find how the project already solves the same problem, and base the recommendation on that part.
3. Write the answer in the rule's four-part shape and keep it in the loop state. Nothing is published during the loop.
4. When the answer shows a defect, fix the defect like any other finding in this loop, and let the answer point to that fix.

A question that also asks for a change carries both items: the change and the answer.

## After convergence

- **PR update** adds `## Answers to reviewer questions` to the CR comment, only when the loop answered a question. It holds one entry per question, in the shape `@skills/code-review-github/references/cr-wrapper-contract.md` *Output Rules* defines. Before you publish, re-read every `file:line` each answer cites on the final head. Correct an answer whose evidence changed during the loop.
- **Resolve addressed reviewer threads** leaves a thread that only asked a question unresolved after its answer is published. The asker decides whether the answer is sufficient.
- **Completion** adds one line to the in-conversation report: the number of answered questions, and every point an answer marked *Not verified*.
