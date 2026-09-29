# ssh-triangle

A small bash helper for SSH jump-host access: host reachability checks,
direct-vs-via-jump latency comparison, and generation of a ready-to-use
`ssh -J` command plus a `~/.ssh/config` block.

The point: reaching a host behind a firewall or a slow route usually needs one
jump host and two lines of config — not a second VPS with a proxy chain.

## Commands

```bash
./ssh_triangle.sh check  <hostA> <hostB> [port]   # TCP reachability of both hosts
./ssh_triangle.sh compare <jump> <target> [port]  # ping direct vs from the jump host
./ssh_triangle.sh gen    <jump> <target> [alias]  # ssh -J one-liner + config block
```

## Example

```console
$ ./ssh_triangle.sh compare vps1.example.com vps2.example.com
Latency measurement (5 icmp packets):
  direct to vps2.example.com              : 182.4 ms
  from jump host (vps1.example.com) to .. : 3.1 ms
  difference (direct - via jump)          : +179.3 ms

Ready-to-use route:
  ssh -J vps1.example.com vps2.example.com
```

`gen` prints a ready block:

```
Host target-via-jump
    HostName vps2.example.com
    ProxyJump user@vps1.example.com:22
    ServerAliveInterval 30
```

## Requirements

- bash, ssh, ping; optionally `nc` (otherwise bash's built-in `/dev/tcp` is used)
- key-based login on the jump host (`ssh-copy-id user@jump`)
- ICMP allowed on both hosts (for the `compare` command)

No third-party dependencies.

## License

MIT
