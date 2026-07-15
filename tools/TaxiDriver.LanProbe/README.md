# TaxiDriver LAN Bridge Test

This project is an automated integration test for the subnet bridge embedded
in TaxiDriver. It is development-only and is not included in `taxidriver.zip`.

## Test

```powershell
dotnet run --project tools/TaxiDriver.LanProbe -- --self-test
```

The test starts a loopback-only fake UI server, creates an in-process bridge,
then connects through the machine's real subnet address. It verifies HTTP and
the bidirectional WebSocket transport used by BeamNG External UI.
