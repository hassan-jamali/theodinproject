#!/bin/bash
docker stop odin-prod-app 2>/dev/null || true
docker rm odin-prod-app 2>/dev/null || true