#!/usr/bin/env bash

BASENAME="${0##*/}"
EXPIRY=86400 # 1 day in seconds

test -z "$OUTDIR" && OUTDIR="$HOME/Movies/trailers/"
test -z "$DATADIR" && DATADIR="${OUTDIR}data/"
hash jq 2>/dev/null || { echo "$BASENAME requires jq (brew install jq)"; exit 1; }
hash pup 2>/dev/null || { echo "$BASENAME requires pup (brew install pup)"; exit 1; }

TMP_DIR=$(mktemp -d "$TMPDIR$BASENAME.XXXXXX") || { echo "$BASENAME: can't create the temp dir at: $TMPDIR"; exit 1; }
TMP_MARKERFILE="$TMP_DIR/marker"
trap "rm -rf '$TMP_DIR'" EXIT

function __curl () {
  local AE AL UA Ac Rf Cn Ra
  #AE="Accept-Encoding: identity;q=1, *;q=0"
  AL="Accept-Language: en-US,en;q=0.8"
  #UA="User-Agent: QuickTime/7.6.2"
  UA="User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36"
  Ac="Accept: */*"
  #Rf="Referer: $1"
  Cn="Connection: keep-alive"
  # TODO: add resuming
  #Ra="Range: bytes=0-"
  curl -H "$AL" -H "$UA" -H "$Ac" -H "$Cn" "$@"
}

function __expired () {
  #test $(expr $(date +%s) - $(date -r "$1" +%s)) -gt $2
  test $(expr $(date +%s) - $(stat -f "%m" "$1")) -gt $2
}

function __fetchFeed () {
  local FEED FEED_BASENAME FEED_FILE HTTP_RESPONSE
  FEED="$1"
  FEED_BASENAME=$(basename "$FEED")
  FEED_FILE="$TMPDIR$BASENAME.feed.$FEED_BASENAME"
  test -e "$FEED_FILE" && __expired "$FEED_FILE" "$EXPIRY" && mv "$FEED_FILE" "$FEED_FILE.bak" && echo >&2 "$BASENAME: backed expired trailers feed"

  if test -e "$FEED_FILE"; then
    HTTP_RESPONSE=$(cat "$FEED_FILE")
  else
    echo >&2 "$BASENAME: fetching trailers feed"
    HTTP_RESPONSE=$(__curl -L -s "$FEED") || { echo >&2 "$BASENAME: error fetching trailers feed"; exit 1; }
    test -n "$HTTP_RESPONSE" && echo "$HTTP_RESPONSE" > "$FEED_FILE"
  fi

  echo "$HTTP_RESPONSE"
}

#function __processXMLFeed () {
#  pup 'a + a attr{href}'
#}

function __processJSONFeed () {
  jq -r '.[] | "http://trailers.apple.com" + .location'
}

# NOTE: keep in mind that the XML feed is with smaller number of items
#HTTP_RESPONSE=$(__fetchFeed "http://images.apple.com/trailers/home/rss/newtrailers.rss")
#LOCATIONS=$(echo "$HTTP_RESPONSE" | __processXMLFeed)
HTTP_RESPONSE=$(__fetchFeed "http://trailers.apple.com/trailers/home/feeds/just_added.json")
LOCATIONS=$(echo "$HTTP_RESPONSE" | __processJSONFeed)

echo "$LOCATIONS" | while read HREF; do
  test -e "$TMP_MARKERFILE" && echo "\n\n** Interrupted" && exit 2

  TRAILER_BASENAME=$(basename "$HREF")
  #test "$TRAILER_BASENAME" != "theinvitation" && continue
  TRAILER_HTMLFILE="$TMPDIR$BASENAME.page.$TRAILER_BASENAME.html"
  REF="Referer: $HREF"

  test -e "$TRAILER_HTMLFILE" && __expired "$TRAILER_HTMLFILE" "$EXPIRY" && mv "$TRAILER_HTMLFILE" "$TRAILER_HTMLFILE.bak" && echo >&2 "$TRAILER_BASENAME: backed expired page"

  if test -e "$TRAILER_HTMLFILE"; then
    TRAILER_RESPONSE=$(cat "$TRAILER_HTMLFILE")
  else
    echo >&2 "$TRAILER_BASENAME: fetching trailer page"
    TRAILER_RESPONSE=$(__curl -L -s "$HREF") || echo >&2 "error fetching trailer page"
    test -n "$TRAILER_RESPONSE" && echo "$TRAILER_RESPONSE" > "$TRAILER_HTMLFILE"
  fi

  if test -n "$TRAILER_RESPONSE"; then

    TRAILER_ID=$(echo "$TRAILER_RESPONSE" | pup "meta[name=apple-itunes-app]" | sed -n '/.*movie\/detail\/\([0-9]*\).*/{s//\1/p;q;}')

    if test -z "$TRAILER_ID"; then
      echo >&2 "$TRAILER_BASENAME: couldn't get the id"
    else

      #TRAILER_JSONFILE="$TMPDIR$BASENAME.$TRAILER_BASENAME.$TRAILER_ID.json"
      TRAILER_JSONFILE="$DATADIR$TRAILER_BASENAME.$TRAILER_ID.json"

      test -e "$TRAILER_JSONFILE" && __expired "$TRAILER_JSONFILE" "$EXPIRY" && mv "$TRAILER_JSONFILE" "$TRAILER_JSONFILE.bak" && "$TRAILER_BASENAME: backed expired json"

      if test -e "$TRAILER_JSONFILE"; then
        JSON_RESPONSE=$(cat "$TRAILER_JSONFILE")
      else
        echo >&2 "$TRAILER_BASENAME: fetching trailer json"
        TRAILER_JSON="http://trailers.apple.com/trailers/feeds/data/$TRAILER_ID.json"
        JSON_RESPONSE=$(__curl -L -s -H "$REF" "$TRAILER_JSON") || { echo >&2 "$TRAILER_BASENAME: error fetching trailer json"; JSON_RESPONSE=""; }
        #JSON_RESPONSE=$(echo "$JSON_RESPONSE" | jq '.') || { echo >&2 "$TRAILER_BASENAME: invalid json"; JSON_RESPONSE=""; }
        if test -n "$JSON_RESPONSE"; then
          if test ! -d "$DATADIR"; then
            mkdir -p "$DATADIR" || { echo >&2 "$BASENAME: couldn't create $DATADIR"; exit 1; }
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
        # strip new line chars, since jq has issues with those. a better solution would be to escape them.
        JSON_RESPONSE=$(echo "$JSON_RESPONSE" | tr -d "\r\n")
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
              RANGE=
              TRAILER_FILE_BASENAME=$(basename "$URL")
              TRAILER_FILE="$TRAILER_OUTDIR$TRAILER_FILE_BASENAME"
              # TODO: use xattr, if available
              CONTENTLENGTH_FILE="$DATADIR$TRAILER_FILE_BASENAME.contentlength.txt"
              CONTENTLENGTH=$(cat "$CONTENTLENGTH_FILE" 2>/dev/null)

              if test -e "$TRAILER_FILE.part"; then
                FILESIZE=$(stat -f "%z" "$TRAILER_FILE.part" 2>/dev/null)
                test "$CONTENTLENGTH" -gt "$FILESIZE" && RANGE="Range: bytes=${FILESIZE}-"
              fi

              if test ! -e "$TRAILER_FILE" -o -n "$RANGE"; then
                echo >&2 "$TRAILER_BASENAME: downloading trailer for $MOVIE_TITLE - $TRAILER_FILE_BASENAME"
                #echo "$URL"
                touch "$TMP_MARKERFILE"

                if test -z "$CONTENTLENGTH"; then
                  #Content-Length: 72828515
                  #Content-Type: video/m4v
                  #Cache-Control: max-age=900
                  CONTENTLENGTH=$(__curl -I -L -# -H "$REF" "$URL" | grep -ie '^Content-Length: ' | sed 's/.*: *\([0-9]*\).*/\1/')
                  test "$CONTENTLENGTH" -gt 0 && echo "$CONTENTLENGTH" > "$CONTENTLENGTH_FILE"
                fi

                STATUS=
                if test -n "$RANGE"; then
                  echo >&2 "$TRAILER_BASENAME: resuming download at "$FILESIZE" byte"
                  __curl -L -# -H "$REF" -H "$RANGE" "$URL" >> "$TRAILER_FILE.part" && STATUS=$? || { STATUS=$?; echo "$TRAILER_BASENAME: error downloading the trailer"; }
                else
                  __curl -L -# -H "$REF" "$URL" > "$TRAILER_FILE.part" && STATUS=$? || { STATUS=$?; echo "$TRAILER_BASENAME: error downloading the trailer"; }
                fi
                test "$STATUS" -eq 0 && mv "$TRAILER_FILE.part" "$TRAILER_FILE"
                # TODO: queue the files to resume/retry
                rm "$TMP_MARKERFILE"
              fi
            done
          fi
        fi
      fi
    fi
  fi
done

exit 0
