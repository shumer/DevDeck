# 0039 - One Arc stack at a time, said before it is done

## Status

Accepted.

## Context

Fusion's local stack names its containers the same in every checkout and serves on one port.
Starting the stack of a second organization therefore takes the first one down, whoever started
it. The deck saw that as the first project having "stopped on its own", with a banner that said
something broke, which is how a start pressed by an agent for one newspaper became an alert
about another.

## Decision

**A start that takes another stack down is that stack's stop, and is treated as one.** Before
starting or restarting an Arc project while another Arc card is up, the runtime stops the other
one itself: the stop goes on record (as the agent's when an agent asked), the other card says it
is stopping and then that it gave way, the starting card says what it is waiting for, and only
then does `fusion daemon` run. The watch has a state for it, `replaced(by:)`, which is a Good to
know row and never a banner: it was asked for.

**The person is asked first, on the card.** Start and Restart carry a confirmation when another
stack is up, the same `DeckConfirmation` the menu's Power off DDEV carries, and both shells ask
it before sending the command. The model names which buttons ask; a shell only asks.

**An agent is refused first.** `start_project` and `restart_project` answer with the running
card's name and nothing happens until the agent passes `replace: true`. An agent that did not
know about the other stack should not take it down on the way to its own.

**A takeover seen from outside is read the same way.** The local loop asks every stack before
judging any: a project that was up and is down with no stop on record, while another Arc stack
is up on the same pass, gave way; a project that is down with nothing up in its place stopped on
its own, as before.

## Consequences

- Only Arc projects know about each other this way. DDEV and plain projects have their own
  ports and names and can run side by side.
- The rival is the first other enabled Arc project whose stack is up. Two stacks cannot both be
  up, so there is at most one.
- A stop that does not take effect is reported as such and the start goes ahead anyway: Fusion
  would have replaced the containers regardless, and the card for the other stack says what
  happened.
