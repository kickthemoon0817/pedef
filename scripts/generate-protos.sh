#!/usr/bin/env bash
# generate-protos.sh — Generate Swift code from .proto definitions
#
# Prerequisites:
#   brew install swift-protobuf protoc-gen-grpc-swift
#
# Usage:
#   ./scripts/generate-protos.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_DIR="$ROOT_DIR/Protos"
OUT_DIR="$ROOT_DIR/PedefSync/Sources/Generated"

echo "==> Generating Swift from .proto files"
echo "    Proto dir: $PROTO_DIR"
echo "    Output dir: $OUT_DIR"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Check tools
for tool in protoc protoc-gen-swift protoc-gen-grpc-swift-2; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: $tool not found. Install with: brew install swift-protobuf protoc-gen-grpc-swift"
    exit 1
  fi
done

# Generate message types (.pb.swift)
protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$OUT_DIR" \
  --swift_opt=Visibility=Public \
  "$PROTO_DIR"/pedef_models.proto \
  "$PROTO_DIR"/pedef_sync.proto \
  "$PROTO_DIR"/pedef_papers.proto

# Generate gRPC service stubs (.grpc.swift)
# Only for files that define services (sync and papers, not models)
protoc \
  --proto_path="$PROTO_DIR" \
  --grpc-swift-2_out="$OUT_DIR" \
  --grpc-swift-2_opt=Visibility=Public \
  "$PROTO_DIR"/pedef_sync.proto \
  "$PROTO_DIR"/pedef_papers.proto

echo "==> Generated files:"
ls -la "$OUT_DIR"/*.swift 2>/dev/null || echo "    (no files generated)"
echo "==> Done"

