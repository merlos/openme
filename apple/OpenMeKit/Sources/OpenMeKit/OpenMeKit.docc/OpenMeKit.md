# ``OpenMeKit``

Swift framework that implements the openme Single Packet Authentication (SPA)
client protocol for Apple platforms (macOS, iOS, watchOS).

## Overview

OpenMeKit lets any Apple-platform app send an authenticated SPA knock to an
openme server, causing the server's firewall to temporarily open the requested
ports for the knocking IP address — without the server ever exposing a
permanently open TCP port.

The library is split into four layers:

| Layer | Type | Role |
|-------|------|------|
| ``KnockService`` | `enum` | Low-level packet builder and UDP sender |
| ``KnockManager`` | `class` | High-level per-profile knock orchestration, continuous mode |
| ``ProfileStore`` | `class` | Persistent profile store backed by `config.yaml` |
| ``ClientConfigParser`` | `enum` | YAML serialiser / deserialiser for the shared config format |

> **Protocol details** — The cryptography, packet layout, and handshake
> sequence are specified in the openme documentation:
> - [Packet Format](https://openme.merlos.org/docs/protocol/packet-format.html)
> - [Handshake](https://openme.merlos.org/docs/protocol/handshake.html)
> - [Cryptography](https://openme.merlos.org/docs/protocol/cryptography.html)
> - [Replay Protection](https://openme.merlos.org/docs/protocol/replay-protection.html)

## Topics

### Getting started

- <doc:GettingStarted>

### Knocking

- ``KnockService``
- ``KnockManager``
- ``KnockServiceError``

### Profiles

- ``Profile``
- ``ProfileEntry``
- ``ProfileStore``

### Config serialisation

- ``ClientConfigParser``

### Notifications

- ``Notifications``
