#!/bin/bash
# /usr/local/bin/sendmail-fake.sh

MESSAGE=$(cat)

notify-send -t 5000 "Sendmail message" "$MESSAGE" --icon=dialog-information

exit 0

