#!/bin/bash
read -p "Commit description: " desc
git commit -m "$desc"
git push origin master
ssh -t m13515002@167.205.32.100 'cd bc && git pull'
