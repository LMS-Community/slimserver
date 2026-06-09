# Tests

Run the tests from the project's root folder like eg.:

```shell
perl -I$PWD/CPAN/arch/5.34/ -I$PWD/CPAN/arch/5.34/darwin-thread-multi-2level/auto t/gdresizer_explicit_format.t
```

Adjust the `-I` path to your platform to allow the tests to pick up the correct binaries if needed.