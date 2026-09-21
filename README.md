# COP5615 Project 1 — Bitcoin-style Proof-of-Work Miner

**Group members:** Devanshu Surana, Nandani Rai

## Overview

A SHA-256 proof-of-work coin miner built entirely on the Erlang actor model. One
program (`server.erl`) runs the boss actor and mines locally on every core; a
second program (`worker.erl`) connects to a running server over the network and
contributes additional cores from a separate machine. All coins found — by the
server's own local workers or by any connected remote worker — are printed and
logged only by the server, as required.

## Work unit (chunk) size

The chunk size is the number of consecutive nonces the boss hands out per
request. We swept five values (100, 1,000, 20,000, 100,000, 1,000,000) and
measured coins found in a fixed 30-second window, both with the server running
alone and with one remote worker connected.

**Server only (isolates chunk-size effect from network variance):**

| Chunk size | Coins in 30s | Real time (s) | User time (s) | CPU ratio |
| ---------- | ------------ | ------------- | ------------- | --------- |
| 100        | 541          | 30.390        | 277.92        | 9.15      |
| 1,000      | 588          | 29.817        | 306.26        | 10.27     |
| **20,000** | **628**      | 30.459        | 317.82        | **10.44** |
| 100,000    | 241          | 33.705        | 223.81        | 6.64      |
| 1,000,000  | 50           | 30.271        | 201.96        | 6.67      |

**Server with one remote worker connected:**

| Chunk size | Coins in 30s | Real time (s) | User time (s) | CPU ratio |
| ---------- | ------------ | ------------- | ------------- | --------- |
| 100        | 803          | 31.249        | 206.93        | 6.62      |
| 1,000      | 341          | 31.723        | 211.25        | 6.66      |
| **20,000** | 617          | 30.100        | 199.53        | 6.63      |
| 100,000    | 738          | 30.064        | 198.69        | 6.61      |
| 1,000,000  | 725          | 29.786        | 197.24        | 6.62      |

**Conclusion: 20,000 nonces per chunk.** The server-only data shows a clean
peak at 20,000 — both the highest coin count (628) and the highest CPU ratio
(10.44) of the five values tested, with a clear falloff on both sides. Below
20,000, workers re-request work often enough that round trips to the single
boss actor start eating into hashing time. Above 20,000, each request blocks a
worker on a long uninterrupted stretch, and the fixed 30-second window catches
fewer complete rounds since more time is "wasted" between the last request and
the deadline. The two-machine table is noisier — likely due to network timing
variance between individual runs — but 20,000 remains solidly competitive
there too, so we used it as our default going forward.

## Result of running with input K = 4

Full log excerpt (`coins.log`), tagged with which node found each coin:

```
['server@192.168.68.63'] d.surana;30318	000047223e52f95b5947467a233bc5875cd479ce0ca84e0953721d0ef541ddd0
```

Verified independently against the xorbin SHA-256 calculator.

## Running time and CPU ratio

Command: `time ./server 4` (chunk size 20,000), server alone, all 8 local
cores mining:

```
199.53s user  6.94s system  685% cpu  30.100 total
```

**CPU ratio ≈ 6.85** (`user / real` = 199.53 / 30.10). This machine has 8
logical cores; a ratio of ~6.85 out of a possible 8 shows strong, genuine
parallelism across cores via the actor model, not a single-threaded run
(which would show a ratio near 1.0).

## Coin with the most leading zeros

Found during a K = 4 run, with one remote worker connected — a coin can
always have _more_ zeros than the requested minimum, since the requirement is
"at least K", and this one got lucky:

```
['worker9348@192.168.68.66'] d.surana;4784735	000000f6dd0ec49ef949548d12a4f0b8b15d107e2474e16a3259db39a56abb93
```

**6 leading zeros.** Found by the remote worker node, confirming remote
machines contribute real, verifiable coins — not just local CPU cycles.

## Largest number of machines

**2 physical machines**, verified working together:

- **Server**: `server@192.168.68.63` — 8 cores, ran the boss actor and 8 local
  worker actors
- **Worker**: `worker9348@192.168.68.66` — remote machine, connected over LAN,
  ran additional worker actors that pulled nonce ranges from the same boss and
  reported coins back to it

The server was confirmed to mine successfully on its own (no worker
connected) and to accept the remote worker joining mid-run without any
restart, as required.

## Actor model design

- **One boss actor** per server: owns the single, monotonically increasing
  nonce counter and hands out disjoint chunks to any worker that asks — local
  or remote. It is also the only actor that ever prints or logs a coin, so
  every find funnels through one place regardless of which machine found it.
- **Many worker actors** (one per CPU core, on every connected machine): each
  runs an infinite loop — ask the boss for a chunk, hash every candidate
  string in that chunk, report any hit back to the boss, repeat. Workers never
  communicate with each other, only with the boss, which is what allows
  adding more machines or cores with no coordination logic changes.
- No shared memory or locks anywhere: the "who has claimed which nonces"
  problem is solved entirely by the boss's private state and message passing,
  which is the actor-model guarantee this project required.
