#!/usr/bin/env bash

BASENAME="${0##*/}"

test -z "$OUTDIR" && OUTDIR="$HOME/Movies/trailers/"
hash jq 2>/dev/null || { echo "$BASENAME requires jq (brew install jq)"; exit 1; }
hash pup 2>/dev/null || { echo "$BASENAME requires pup (brew install pup)"; exit 1; }

function __curl () {
  local AE AL UA Ac Rf Cn Ra
  #AE="Accept-Encoding: identity;q=1, *;q=0"
  AL="Accept-Language: en-US,en;q=0.8"
  UA="User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36"
  Ac="Accept: */*"
  #Rf="Referer: $1"
  Cn="Connection: keep-alive"
  #Ra="Range: bytes=0-"
  curl -H "$AL" -H "$UA" -H "$Ac" -H "$Cn" "$@"
}

function __expired () {
  #test $(expr $(date +%s) - $(date -r "$1" +%s)) -gt $2
  test $(expr $(date +%s) - $(stat -f "%m" "$1")) -gt $2
}

#FEED_TMPFILE=$(mktemp "$TMPDIR$BASENAME.XXXXXX") || { echo &>2 "cannot make temp file for the feed"; exit 1; }
FEED_FILE="$TMPDIR$BASENAME.feed.xml"
#trap "rm '$FEED_TMPFILE'" EXIT
EXPIRY=86400 # 1 day in seconds
test -e "$FEED_FILE" && __expired "$FEED_FILE" "$EXPIRY" && mv "$FEED_FILE" "$FEED_FILE.bak" && echo >&2 "$BASENAME: backed expired trailers feed"

if test -e "$FEED_FILE"; then
  HTTP_RESPONSE=$(cat "$FEED_FILE")
else
  echo >&2 "$BASENAME: fetching trailers feed"
  FEED=http://images.apple.com/trailers/home/rss/newtrailers.rss
  #curl -L -s "$FEED" > "$FEED_TMPFILE" || { echo >&2 "$BASENAME: error fetching feed"; exit 1; }
  HTTP_RESPONSE=$(__curl -L -s "$FEED") || { echo >&2 "$BASENAME: error fetching trailers feed"; exit 1; }
  test -n "$HTTP_RESPONSE" && echo "$HTTP_RESPONSE" > "$FEED_FILE"
fi

#trap - EXIT

echo "$HTTP_RESPONSE" | pup 'a + a attr{href}' | while read HREF; do
  TRAILER_BASENAME=$(basename "$HREF")
  #test "$TRAILER_BASENAME" != "theinvitation" && continue
  TRAILER_HTMLFILE="$TMPDIR$BASENAME.$TRAILER_BASENAME.html"
  REF="Referer: $HREF"

  test -e "$TRAILER_HTMLFILE" && __expired "$TRAILER_HTMLFILE" "$EXPIRY" && mv "$TRAILER_HTMLFILE" "$TRAILER_HTMLFILE.bak" && echo >&2 "$TRAILER_BASENAME: backed expired page"

  if test -e "$TRAILER_HTMLFILE"; then
    TRAILER_RESPONSE=$(cat "$TRAILER_HTMLFILE")
  else
    echo >&2 "$TRAILER_BASENAME: fetching trailer page"
    TRAILER_RESPONSE=$(__curl -L "$HREF") || echo >&2 "error fetching trailer page"
    test -n "$TRAILER_RESPONSE" && echo "$TRAILER_RESPONSE" > "$TRAILER_HTMLFILE"
  fi

  if test -n "$TRAILER_RESPONSE"; then

    TRAILER_ID=$(echo "$TRAILER_RESPONSE" | pup "meta[name=apple-itunes-app]" | sed -n '/.*movie\/detail\/\([0-9]*\).*/{s//\1/p;q;}')

    if test -z "$TRAILER_ID"; then
      echo >&2 "$TRAILER_BASENAME: couldn't get the id"
    else

      #TRAILER_JSONFILE="$TMPDIR$BASENAME.$TRAILER_BASENAME.$TRAILER_ID.json"
      TRAILER_JSONFILE="$OUTDIR$TRAILER_BASENAME.$TRAILER_ID.json"

      test -e "$TRAILER_JSONFILE" && __expired "$TRAILER_JSONFILE" "$EXPIRY" && mv "$TRAILER_JSONFILE" "$TRAILER_JSONFILE.bak" && "$TRAILER_BASENAME: backed expired json"

      if test -e "$TRAILER_JSONFILE"; then
        JSON_RESPONSE=$(cat "$TRAILER_JSONFILE")
      else
        echo >&2 "$TRAILER_BASENAME: fetching trailer json"
        TRAILER_JSON="http://trailers.apple.com/trailers/feeds/data/$TRAILER_ID.json"
        JSON_RESPONSE=$(__curl -L -s -H "$REF" "$TRAILER_JSON") || { echo >&2 "$TRAILER_BASENAME: error fetching trailer json"; JSON_RESPONSE=""; }
        #JSON_RESPONSE=$(echo "$JSON_RESPONSE" | jq '.') || { echo >&2 "$TRAILER_BASENAME: invalid json"; JSON_RESPONSE=""; }
        if test -n "$JSON_RESPONSE"; then
          if test ! -d "$OUTDIR"; then
            mkdir -p "$OUTDIR" || { echo >&2 "$BASENAME: couldn't create $OUTDIR"; exit 1; }
          fi
          echo "$JSON_RESPONSE" > "$TRAILER_JSONFILE" || echo >&2 "$TRAILER_BASENAME: couldn't store JSON"
        fi
      fi

#      JSON_RESPONSE=$(cat <<EOF
#{"clips":[
#  {"versions":{"enus":{"sizes":{"hd720":{"src":"hello"}}}}},
#  {"versions":{"enus":{"sizes":{"not-hd720":{"src":"hello"}}}}}
#]}
#EOF
#)
      if test -n "$JSON_RESPONSE"; then
        MOVIE_TITLE=$(echo "$JSON_RESPONSE" | jq -r '.page.movie_title' | grep -ve '^null$' | tr ':' '_')
        if test -n "$MOVIE_TITLE"; then
          TRAILER_URL=$(echo "$JSON_RESPONSE" | jq -r '.clips[].versions.enus.sizes.hd720.srcAlt' | grep -ve '^null$')
          test -z "$TRAILER_URL" && TRAILER_URL=$(echo "$JSON_RESPONSE" | jq -r '.clips[].versions.enus.sizes.hd1080.srcAlt' | grep -ve '^null$')
          test -z "$TRAILER_URL" && TRAILER_URL=$(echo "$JSON_RESPONSE" | jq -r '.clips[].versions.enus.sizes.sd.srcAlt' | grep -ve '^null$')
          test -z "$TRAILER_URL" && echo "$TRAILER_BASENAME: couldn't find any trailers"

          if test -n "$TRAILER_URL"; then
            TRAILER_OUTDIR="$OUTDIR$MOVIE_TITLE/"
            if test ! -d "$TRAILER_OUTDIR"; then
              mkdir -p "$TRAILER_OUTDIR" || { echo >&2 "$BASENAME: couldn't create $TRAILER_OUTDIR"; exit 1; }
            fi

            echo "$TRAILER_URL" | while read URL; do
              TRAILER_FILE_BASENAME=$(basename "$URL")
              TRAILER_FILE="$TRAILER_OUTDIR$TRAILER_FILE_BASENAME"
              if test ! -e "$TRAILER_FILE"; then
                echo >&2 "$TRAILER_BASENAME: downloading trailer for $MOVIE_TITLE - $TRAILER_FILE_BASENAME"
                #echo "$URL"
                __curl -L -# -H "$REF" "$URL" > "$TRAILER_FILE" || echo "$TRAILER_BASENAME: error downloading the trailer"
              fi
            done
          fi
        fi
      fi
    fi
  fi
done

exit 0
