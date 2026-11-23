---
title: "Introducing cl-stack"
date: 2026-11-23 17:16
tags: [lisp, cl-stack, cl-repo, windows, ai]
---

Today I want to introduce [cl-stack](https://github.com/egao1980/cl-stack), a set of Common Lisp libraries I've been thinking about for a long time.

Every time I start writing a Common Lisp program, I end up a bit frustrated: some library is missing, or half-baked, or outdated, or doesn't work with some modern technology, you name it. It could be HTTP/2, it could be gRPC. It could be something that works only on Linux, because it binds a foreign library with CFFI and the groveller, which is probably not available on Windows. Then you switch to Mac and you are in a sea of pain again. But Windows is the main culprit.

So over the years I was dreaming about a system that solves these problems. I'm coming from the Python world, and Python has a few solutions to that. One of them is Anaconda, or Conda. It's not the best system in the world, but it did a lot of good for the Python community. It provides exactly that: pre-built libraries, a set of almost universally available libraries and tools. The price is some additional effort when packaging your library or product.

<!--more-->

## Why now

I had no budget, team or time to do it myself. So it lingered as a nagging thought in my head for a long time, waiting for an opportunity to come.

Now, with the advancement of AI, I can do a lot as a single developer. I'm basically acting as an architect and project lead for my team of AI agents: Cursor, Claude, or even local AI models. I steer them and they do the job. It costs some money, and yes, it heats up the universe, but as a result I have something I want to share with the world.

## What it is

In ambition it's something like LispWorks, but in shape it resembles Conda more. It is built around simple principles and a few core tools.

### cl-repo

The first one is [cl-repository](https://github.com/egao1980/cl-repository), or `cl-repo`, a tool to build projects and get their dependencies. It uses standard OCI images and OCI registries to store systems and their metadata.

It's backwards compatible with the tools we already have. A stock `.asd` is enough, and `cl-repo` installs `qlfile` / `qlfile.lock` like [qlot](https://github.com/fukamachi/qlot) does. Quicklisp and Ultralisp dists can be mirrored into an OCI registry. And it works with [OCICL](https://github.com/ocicl/ocicl) both ways: `cl-repo` pulls OCICL packages, and the OCICL client installs `cl-repo` ones.

It is built around the notion of overlays. When you build a system, you can create additional overlays with files specific to a platform, an architecture and a Lisp implementation. That includes native libraries pre-built for that exact combination, which solves another problem: distributing native libraries across platforms. That opened up huge opportunities for me to progress further.

```sh
cl-repo sync   # install the dependencies from the .asd
cl-repo test   # run the system's tests in a fresh image
```

### Protocols and backends

Building on that, I've instructed AI to implement proper redistributable native wrappers for Windows, Linux and macOS, plus Java-based ones for ABCL. On top of them there are CLOS protocol-based systems covering:

* internationalization, date and time handling, and Unicode strings (ICU);
* compression and encodings: Brotli, Zstandard, Snappy, gzip via chipz;
* transports and wire protocols, from HTTP/1.1 and HTTP/2 to WebSockets, gRPC and JSON-RPC;
* and many, many more, including, obviously, AI-related protocols (MCP, A2A, AG-UI, ACP).

Whenever possible I used native library bindings, like libuv or libev for async support. I reused many very well designed libraries, like Alexandria, the trivial-* libraries, Bordeaux Threads and whatnot. I was standing on the shoulders of giants.

But when it was practical, I re-implemented things from scratch in a single consistent approach. A feature like the HTTP protocol is described as a number of CLOS classes and generic functions, and then backends implement it. For example, I have HTTP clients based on Dexador, on libuv or libev depending on the system, and one that uses Java's HTTP client, available in ABCL. Each system gets the protocol definition and builds against it, and the backends are pluggable. That is used across the whole stack.

It also means one protocol solves the same kind of problem everywhere. When I needed a rule-based system for a coding agent harness, I didn't write yet another allow/deny list resolver. I reused the SAT protocol, which already solves similar problems in a few other places, and the logic protocol, a Datalog implementation, to complete it.

> **Achievement unlocked: [cl-stack-code](https://github.com/egao1980/cl-stack-code).** A functional coding agent harness built on the stack, with skills, MCPs, sandboxing, versioning, image-based development and a rich Common Lisp toolkit.

## Not a standard library

So that's the main theme: I'm trying to fill the gaps. I looked at the most used libraries in Python, Java, TypeScript and other languages and compared them with the current Common Lisp surface. Common Lisp is a good language, but it lacks standard library implementations. I'm trying not to be too ambitious and call this a standard library. No. It's a practical set of libraries for working on modern software.

That's how it is. Everything is on GitHub: [cl-stack](https://github.com/egao1980/cl-stack) (docs and a [quickstart](https://github.com/egao1980/cl-stack/blob/main/docs/QUICKSTART.md)) and [cl-repository](https://github.com/egao1980/cl-repository).
