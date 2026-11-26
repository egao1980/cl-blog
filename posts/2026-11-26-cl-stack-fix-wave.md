---
title: "Three days of cl-stack fixes: adversarial reviews, one lane at a time"
date: 2026-11-26 16:00
tags: [lisp, cl-stack, cl-repo, ai]
---

After the [Python to Common Lisp](https://egao1980.github.io/python-to-cl/) review turned up a list of gaps in cl-stack, I spent three days closing them with agents. This is what shipped, how the work was organised, and what went wrong along the way.

<!--more-->

## How the work ran

Each gap got a pair of agents. One tried to fix it. The other tried to prove it was still broken: it wrote a failing test for every break it could find, against a live broker, mail server or proxy where it mattered. A fix merged only when CI was green on Linux, macOS and Windows and the adversarial round found nothing real.

This found a lot. Every services release went through several rounds:
- The AMQP backend acked the wrong message after a channel reopen.
- mime-protocol let CR/LF into headers.
- mail-protocol silently dropped recipients after a group's `;`.

Each break became a test before it became a fix.

For the larger features I used the team-solve flow:
- a contract PR with failing tests and stubs;
- fresh agents for plan, solve, review and repair;
- `check-feature.sh` as the only verdict.

## What shipped

All of it is on GHCR, and the details are on the site's [Updates page](https://egao1980.github.io/python-to-cl/updates.html).

- **HTTP:** `https://` proxies now get TLS. Proxy credentials no longer leak on a redirect. A session `:proxy` wins over the environment, and redirect methods follow RFC 9110. The Windows timeout fixes are in http-backend-dexador. Demos: [http-facade](https://github.com/egao1980/cl-stack-demos/tree/main/harness/http-facade), [dexador-http](https://github.com/egao1980/cl-stack-demos/tree/main/harness/dexador-http).
- **Mail:** mime-protocol 0.3.4 and mail-protocol 0.3.2. Header and SMTP injection are refused, addresses go through an RFC 5322 parser, and long non-ASCII attachment names use RFC 2231 continuations, cross-checked against Python's `email`.
- **Services:** cache-backend-redis 0.2.1, mq-backend-amqp 0.2.2 and mq-backend-kafka 0.2.2, with native librdkafka for four platforms. Demos: [services](https://github.com/egao1980/cl-stack-demos/tree/main/harness/services), [s3-minio](https://github.com/egao1980/cl-stack-demos/tree/main/harness/s3-minio).
- **cl-stack-code:**
  - 0.14.0: retries by failure class, timeouts and compaction ([code-resilience](https://github.com/egao1980/cl-stack-demos/tree/main/harness/code-resilience)).
  - 0.15.0: plan mode, where plans are documents you edit, approve or reject ([plan](https://github.com/egao1980/cl-stack-demos/tree/main/harness/plan)).
  - 0.16.0: MCP sampling, elicitation and deferred tool loading ([code-mcp-requests](https://github.com/egao1980/cl-stack-demos/tree/main/harness/code-mcp-requests)).
- **Tooling:** lisp-mcp 0.7.3, whose structural edits now keep `#+`/`#-` branches and comments and indent like SLIME, and the cl-repo client 0.27.39.
- **Upstream:** a small quri fix, so that userinfo before an IPv6 literal parses ([fukamachi/quri#94](https://github.com/fukamachi/quri/pull/94)).

## What went wrong

- **Too many lanes at once.** For a while eight agents worked in parallel. They filled the disk: Docker stopped and test runs died mid-way. One of them rebased a shared checkout while another was using it. Since then the rule is one fix in progress at a time, with only investigation running alongside. It was faster.
- **macOS CI runners** stopped being assigned for a day, while Linux and Windows ran normally. For that day I merged on Linux plus Windows CI plus a local macOS run.
- **Contract tests can be wrong.** Three times a sealed test couldn't pass against the published stack:
  - a retry bound that ignored the backoff doubling;
  - a test that used `"path"` where the tool takes `"file_path"`;
  - a `LET` binding that another thread never saw.

  The rule now: the coordinator stops and brings the evidence. With my OK it makes one disclosed, test-only commit, re-seals, and runs every step again.

## What's next

Each adversarial round left a short list of lesser findings, filed as issues. The next round starts with those, one at a time.
