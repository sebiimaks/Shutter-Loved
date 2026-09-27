# Device transport

`SerialDiscovery.devices()` lists macOS callout devices through IOKit, with a
directory-listing fallback when the registry provides no usable entries. Device
names are descriptive only: no published USB identity has been validated, so the
user must choose a device. Discovery neither opens nor probes ports.

`SerialConnection` provides asynchronous, receive-only access. Callbacks arrive
on a private serial queue and should return quickly. Hop to the main actor for
presentation changes; capture the presentation model weakly to avoid a callback
ownership cycle. A `.bytes` event is a chunk, not a complete protocol message.
The protocol layer owns line framing, size limits, decoding, and validation.

The `connect` call replaces an existing connection. Each connection retains its
own callback, and the old descriptor finishes cancellation and closes before a
replacement opens. Explicit disconnect/replacement emits `.closed`; errors emit
one terminal `.failed` event instead. A queued connection superseded before it
opens does not emit events. UI callers should still use a connection token when
posting asynchronously to the main actor so old callbacks cannot update a newer
connection's status. Deinitialization also schedules cleanup.

## Compatibility assumptions to verify on physical hardware

- 9600 baud, 8 data bits, no parity, one stop bit, and no software or hardware
  flow control match the original application's PySerial defaults. They are a
  starting point, not a verified manufacturer transport specification.
- The adapter never writes bytes or explicitly changes modem-control lines.
  Opening a USB serial port can itself change DTR/RTS or reset some firmware;
  the driver's behavior needs a real-device test.
- `TIOCEXCL` requests exclusive ownership from the driver. It cannot establish
  whether another application already holds a nonexclusive descriptor, and its
  enforcement depends on the driver. Close the legacy application before using
  the tester here.
- Original termios settings are restored where possible. Restoration can fail
  after unplugging, but the descriptor is still closed. Descriptors are closed
  once, after their dispatch sources have stopped using them.
- Discovery is a snapshot. Refresh after attaching or removing a device;
  unplugging an open device is reported through EOF or a read error. Reconnect
  is explicit, with no blind retry or automatic selection of another device.
- Validate direct USB and hub connections, idle time, repeated reconnects,
  unplug/replug, and a busy port on the actual tester and firmware. A signed,
  sandboxed build additionally needs serial-device entitlement validation.

The implementation follows Apple's native IOKit and POSIX approach documented
in the [Device File Access Guide for Serial Devices](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/WorkingWSerial/WWSerial_SerialDevs/SerialDevices.html).

## Automated validation

`DeviceTransportTests` exercises real Darwin pseudo terminals, including byte
preservation, no transmitted commands or echo, 9600/8N1 configuration, repeated
replacement of the same path, restoration of original settings, explicit
disconnect/reconnect, deinitialization cleanup, and device hangup. An internal
test initializer admits one exact PTY path; the public initializer retains its
callout-path restriction. Waits have a three-second deadline.

The busy-port test first verifies that the local PTY driver enforces
`TIOCEXCL`. When it does not, that case skips with a concrete explanation;
the physical serial driver's exclusive-access behavior still needs testing.
PTY tests exercise operating-system resource handling, not electrical behavior,
USB firmware, physical measurement accuracy, or application sandbox access.
