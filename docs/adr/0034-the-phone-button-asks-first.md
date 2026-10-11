# 0034. The phone button asks the address first

Date: 2026-10-11

## Status

Accepted.

## Context

The phone button swaps `localhost` in a running project's URL for this machine's address on the
network and draws it as a QR code. The rule it hung on was "only while the project is up", because
a code pointing at a port nothing listens on is a worse answer than no button.

Up is not the same as reachable. A dev server bound to localhost answers the health check and
refuses the phone. On Windows the laptop that checked the port showed a second case: Docker running
inside a WSL distribution in NAT mode publishes its ports to the VM, Windows forwards them to its
own `localhost`, and the machine's network address answers nothing, not even from the laptop
itself. The card offered `http://192.168.0.33:8080`, the project was up, and the phone could not
reach it. The DDEV card had only just learned to offer a code at all (its name resolves to
127.0.0.1 everywhere, so it reads the checkout's `bind_all_interfaces` and `host_webserver_port`
instead), and the first thing it offered was a promise it could not keep.

## Decision

Before offering the address, the engine asks it: one HTTP request to the candidate URL from this
machine, after every local refresh pass and after a command brings a project up, for every project
card at once, two seconds each. Any answer counts, an error page included; what matters is that
something listens there. The button appears only for an address that answered, and only while the
candidate is still the one that did, so a laptop that moves networks does not keep a stale yes.

This is the engine's rule, not the shell's: the model carries a URL or it does not, and the
wording in the popover is unchanged.

## Consequences

- A dev server bound to localhost loses the button it used to have. That is the note in the
  popover made true before the fact rather than after it.
- Docker inside WSL without mirrored networking has no button. Turning on `networkingMode=mirrored`
  in `.wslconfig`, or a port proxy, makes the address answer, and the button follows on the next
  pass without the engine knowing which was done.
- One short request per running project per pass, in parallel. A port that answers nothing costs
  the two-second timeout; the pass does not wait for it beyond that.
- The suite checks the rule with the fake HTTP client the health check already uses: an address
  that answers 404 is offered, one that answers nothing is not.
