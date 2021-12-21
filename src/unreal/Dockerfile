# ---------------------------------------------------------------------------
# Copyright (c) 2021 Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
#
# This is a sample to be adjusted in accordance with the project source code
# ---------------------------------------------------------------------------

# Perform the build in an Unreal Engine container image that includes the Engine Tools and Pixel Streaming for Linux
FROM --platform=${BUILDPLATFORM:-linux/amd64} ghcr.io/epicgames/unreal-engine:dev-4.27 AS builder

# Copy UE4 project (assumes `.uproject` in this directory)
COPY --chown=ue4:ue4 . /tmp/project
WORKDIR /tmp/project

# Package the example Unreal project
RUN /home/ue4/UnrealEngine/Engine/Build/BatchFiles/RunUAT.sh BuildCookRun \
	-clientconfig=Development -serverconfig=Development \
	-project=/tmp/project/PixelStreamingDemo.uproject \
	-utf8output -nodebuginfo -allmaps -noP4 -cook -build -stage -prereqs -pak -archive \
	-archivedirectory=/tmp/project/dist \
	-platform=Linux

# Copy the packaged files into a container image that includes CUDA but doesn't include any Unreal Engine components
FROM --platform=${BUILDPLATFORM:-linux/amd64} ghcr.io/epicgames/unreal-engine:runtime-pixel-streaming
WORKDIR /home/ue4/project
COPY --from=builder --chown=ue4:ue4 /tmp/project/dist/LinuxNoEditor ./

# Establish ENV
ENV RES_X=1920 \
    RES_Y=1080 \
    SIGNAL_URL=ws://127.0.0.1:8888

# Start pixel streaming
CMD ["/bin/bash", "-c", "./PixelStreamingDemo.sh -PixelStreamingURL=${SIGNAL_URL} -RenderOffscreen -Unattended -ForceRes -ResX=${RES_X} -ResY=${RES_Y} -AllowPixelStreamingCommands ${EXTRA_ARGS}" ]
