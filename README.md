# trailers

Fetches latest trailers from a feed.

I wrote this for my personal use. Simply don't use it if it doesn't work for you.

Only tested on Mac OS X 10.10.

## Dependencies

* [jq](https://github.com/stedolan/jq) -- `brew install jq`
* [pup](https://github.com/ericchiang/pup) -- `brew install pup`

## Usage

```
./trailers.sh
```

It will create a directory under `$HOME/Movies/` called `trailers/`.
Then each trailer or clip will go into its own sub-directory.

If you specify an `OUTDIR` environment variable like so:

```
OUTDIR=/some/other/place/ ./trailers.sh
```

it will use that instead of `trailers/`.

__NOTE__: The trailing slash is quite important, so DON'T FORGET IT!

### Temporary files

It writes a lot of temporary files with not-so-useful data to your `TMPDIR` and
some other temporary files with might-be-useful data to a dir, specified by the
`DATADIR`, which defaults to `$OUTDIR/data/`.

### Failures and resuming

If a download fails and stops midway, then the script can resume downloading,
automatically when you execute it again.

__NOTE__: The temporary files are considered expired after 24 hours and will be
re-downloaded.

__NOTE__: If you rename __anything__ the process won't know that file A became called
B, so it will re-download it again. This is out-of-scope of this script.

<hr/>

<small>2016</small>
