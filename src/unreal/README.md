# Unreal Pixel Streaming Runtime

This code is meant to be a starting point for building unreal engine projects
with pixel streaming runtimes in docker.

This is an implemenation using the Unreal dev container (for build) and pixel
streaming runtime. Basic information on these containers can be found in the
[Unreal docs](https://docs.unrealengine.com/4.27/en-US/SharingAndReleasing/Containers/ContainersOverview/)

## Images

The official [Unreal Engine Images](https://github.com/orgs/EpicGames/packages/container/unreal-engine/versions) require GitHub membership with Epic Games, and this is where the `ghcr.io` base images for Unreal are published.

Follow information in the Epic Games [`signup`](https://github.com/EpicGames/Signup)
repository for gaining access.

Because the images are in a private GitHub container registry, you will need to
login any docker client where the images are used. See information how this is done
for [ghcr.io](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)

## Usage

Here are a few notes about the starter [Dockerfile](./Dockerfile), which makes
a few assumptions about project name and directory structure:

1. Change `'.'` to the relative path of the project source (ex: `./PixelStreamingDemo` if in a subdirectory)

    ```dockerfile
    # Copy UE4 project
    COPY --chown=ue4:ue4 . /tmp/project
    ```

1. Change the `.uproject` file name accordingly:

    ```dockerfile
    # Package the example Unreal project
    RUN /home/ue4/UnrealEngine/Engine/Build/BatchFiles/RunUAT.sh BuildCookRun \
      # ...
      -project=/tmp/project/PixelStreamingDemo.uproject \
    ```

1. Change the runtime binary accordingly:

    ```dockerfile
    # Start pixel streaming
    CMD ["/bin/bash", "-c", "./PixelStreamingDemo.sh ..."]
    ```

## Configuration

The sample Dockerfile contains a basic start command with support for Pixel
Streaming command line arguments from the [reference](https://docs.unrealengine.com/4.27/en-US/SharingAndReleasing/PixelStreaming/PixelStreamingReference/)
The following table shows the environment variables, which may be used:

| Variable | About | Default |
|--|--|--|
| `SIGNAL_URL` | Specify websocket url for the signalling server | `ws://localhost:8888` |
| `RES_X` | Force resolution width | `1920` |
| `RES_Y` | Force resolution height | `1080` |
| `EXTRA_ARGS` | Any other commands as a string (ex `-PixelStreamingHideCursor`) | |
