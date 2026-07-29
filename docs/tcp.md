# TCP

The TCP subsystem is a specialized hardware transport engine for deterministic
connection lookup, state updates, transmit payload storage, descriptor
generation, and timeout scheduling. It is not a general-purpose socket stack.

## Data Flow

```text
Received IPv4/TCP header or application request
  -> cache arbiter
  -> tuple cache
  -> TCB manager
      -> tcp_ctrl / tcp_fsm
      -> establish_ctrl
      -> app_ctrl
      -> writeback
      -> RTO
  -> TCP descriptor and optional payload
  -> tx_datapath
```

The tuple cache maps the source/destination IPv4 addresses and ports to one of
64 TCB entries. Received headers and application requests share the lookup
path. Eligible SYN traffic and `TCP_REQ_CONNECT_SEND` requests can allocate a
new cache/TCB address.

Application requests enter through `app_req_in`. A connection request that
needs a destination MAC is retained in the pending-ARP table until
`arp_top_level` returns a matching resolution.

## Connection State

`tcp_fsm` implements the following states:

```text
CLOSED, LISTEN, SYN_RECV, SYN_SENT, ESTABLISHED,
FIN_1, FIN_2, CLOSING, CLOSE_WAIT, LAST_ACK, TIME_WAIT
```

Ingress packets drive state transitions and response flags. `tcp_ctrl` updates
`snd_una` from advancing ACKs, advances `rcv_nxt` only for the expected receive
sequence, constructs response sequence/ACK values, and cancels timeout state
when an ACK covers the transmitted segment.

RST handling invalidates the associated connection rather than producing
another RST. Unexpected flag combinations produce a reset and invalidation in
many states. `TIME_WAIT` currently transitions directly to `CLOSED`; a timed
2MSL wait is not implemented.

## Transmit Payloads and Timeouts

The public RTL retains the interfaces through which application payloads enter
the TCP subsystem and are requested for descriptor issue. The underlying
transmit-memory implementation, internal metadata, and allocation behavior are
intentionally omitted because the subsystem is shared with ongoing private
architectural work.

`rto` schedules TCB addresses and applies increasing backoff state. After the
configured retry limit, the control path emits a reset and invalidates the
connection. Complete payload replay depends on the omitted transmit-memory
subsystem and is not present in this snapshot.

## Receive and Protocol Limitations

- IPv4 and TCP checksums are decoded but are not validated before TCB updates.
- Receive payload delivery to an application is not implemented.
- Out-of-order payload buffering and stream reassembly are not implemented.
- TCP receive-window enforcement, congestion control, slow start, and fairness
  are not implemented.
- TCP options such as MSS, SACK, timestamps, and window scaling are not
  negotiated or processed.
- IPv4 fragment reassembly and IPv6 TCP are not supported.
- Destination MAC and IPv4 address are checked at the top level, but there is
  no independent listening-port policy before tuple-cache allocation.
- The intentionally omitted transmit-memory subsystem prevents the public
  snapshot from operating as a complete transport engine.
- Pending-ARP capacity and surrounding control paths require additional
  backpressure handling.
