# Contributing

Thanks for helping make UMST better. Bug reports, ideas and pull requests are all welcome.

## Getting started

```sh
git clone https://github.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool.git
cd UMST-UltimateMacSchedulingTool
./scripts/test.sh                 # run the tests
./scripts/build.sh                # build build/UMST.app
build/UMST.app/Contents/MacOS/UMST --demo   # run with sample data
```

Only the Xcode Command Line Tools are needed. Please run `./scripts/test.sh` before opening a pull request, and add a test when you fix a parser bug.

## Ground rules

- **Keep UMST about the calendar.** Features that aren't about seeing or adding to your schedule probably belong in a different app.
- **No tracking.** No analytics, telemetry, ads or third-party SDKs.
- **Secrets stay in the Keychain.** Never write links or tokens to files or logs.
- **Don't paste real calendar links or tokens** into issues or pull requests.
- **Original work only.** Only contribute code, images and text you wrote yourself or that come under a license compatible with MIT (say where it came from in the pull request). Don't add other companies' logos or Apple's SF Symbols to icons, the website or marketing images.

## License of contributions

By submitting a contribution, you agree that it is your own work (or that you have the right to submit it) and that it is licensed under the project's [MIT License](LICENSE).

## Conduct

Be kind and constructive. Harassment or abuse of any kind isn't tolerated; maintainers may remove comments, issues or contributors that break this.
