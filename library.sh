#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_DIR="$DIR/lib"
mkdir -p $LIB_DIR

echo "Started '$0' $1 $2 $3 $4"

if [[ ! -z "$1" ]]; then
    TARGET_BUILD_OS="$1"
fi

if [[ ! -z "$2" ]]; then
    TARGET_BUILD_ARCH="$2"
fi

if [[ ! -z "$3" ]]; then
    SDL_LIBRARY_FILE_PATH="$3"
fi

if [[ ! -z "$4" ]]; then
    SDL_INCLUDE_DIRECTORY_PATH="$4"
fi

function set_target_build_os {
    if [[ -z "$TARGET_BUILD_OS" || $TARGET_BUILD_OS == "default" ]]; then
        uname_str="$(uname -a)"
        case "${uname_str}" in
            *Microsoft*)    TARGET_BUILD_OS="microsoft";;
            *microsoft*)    TARGET_BUILD_OS="microsoft";;
            Linux*)         TARGET_BUILD_OS="linux";;
            Darwin*)        TARGET_BUILD_OS="apple";;
            CYGWIN*)        TARGET_BUILD_OS="linux";;
            MINGW*)         TARGET_BUILD_OS="microsoft";;
            *Msys)          TARGET_BUILD_OS="microsoft";;
            *)              TARGET_BUILD_OS="UNKNOWN:${uname_str}"
        esac
        echo "Target build operating system: '$TARGET_BUILD_OS' (default)"
    else
        if [[ "$TARGET_BUILD_OS" == "microsoft" || "$TARGET_BUILD_OS" == "linux" || "$TARGET_BUILD_OS" == "apple" ]]; then
            echo "Target build operating system: '$TARGET_BUILD_OS' (override)"
        else
            echo "Unknown '$TARGET_BUILD_OS' passed as first argument. Use 'default' to use the host build platform or use either: 'microsoft', 'linux', 'apple'."
            exit 1
        fi
    fi
}

function set_target_build_arch {
    if [[ -z "$TARGET_BUILD_ARCH" || $TARGET_BUILD_ARCH == "default" ]]; then
        TARGET_BUILD_ARCH="$(uname -m)"
        echo "Target build CPU architecture: '$TARGET_BUILD_ARCH' (default)"
    else
        if [[ "$TARGET_BUILD_ARCH" == "x86_64" || "$TARGET_BUILD_ARCH" == "arm64" ]]; then
            echo "Target build CPU architecture: '$TARGET_BUILD_ARCH' (override)"
        else
            echo "Unknown '$TARGET_BUILD_ARCH' passed as second argument. Use 'default' to use the host CPU architecture or use either: 'x86_64', 'arm64'."
            exit 1
        fi
    fi
}

set_target_build_os
set_target_build_arch

if [[ "$TARGET_BUILD_OS" == "microsoft" ]]; then
    CMAKE_TOOLCHAIN_ARGS="-DCMAKE_TOOLCHAIN_FILE=$DIR/mingw-w64-x86_64.cmake"
elif [[ "$TARGET_BUILD_OS" == "linux" ]]; then
    CMAKE_TOOLCHAIN_ARGS=""
elif [[ "$TARGET_BUILD_OS" == "apple" ]]; then
    CMAKE_TOOLCHAIN_ARGS=""
else
    echo "Unknown target build operating system: $TARGET_BUILD_OS"
    exit 1
fi

if [[ "$TARGET_BUILD_ARCH" == "x86_64" ]]; then
    CMAKE_ARCH_ARGS="-A x64"
elif [[ "$TARGET_BUILD_ARCH" == "arm64" ]]; then
    CMAKE_ARCH_ARGS="-A arm64"
else
    echo "Unknown target build CPU architecture: $TARGET_BUILD_ARCH"
    exit 1
fi

function exit_if_last_command_failed() {
    error=$?
    if [ $error -ne 0 ]; then
        echo "Last command failed: $error"
        exit $error
    fi
}

function build_sdl() {
    echo "Building SDL..."

    if [[ ! -z "$SDL_LIBRARY_FILE_PATH" ]]; then
        SDL_LIBRARY_FILE_NAME="$(dirname SDL_LIBRARY_FILE_PATH)"
        if [ ! -f "$SDL_LIBRARY_FILE_PATH" ]; then
            echo "Custom SDL library path '$SDL_LIBRARY_FILE_PATH' does not exist!"
        else
            echo "Using custom SDL library path: $SDL_LIBRARY_FILE_PATH"
        fi
    elif [[ "$TARGET_BUILD_OS" == "microsoft" ]]; then
        SDL_LIBRARY_FILE_NAME="SDL2.dll"
        SDL_LIBRARY_FILE_PATH="$LIB_DIR/$SDL_LIBRARY_FILE_NAME"
    elif [[ "$TARGET_BUILD_OS" == "linux" ]]; then
        SDL_LIBRARY_FILE_NAME="libSDL2-2.0.so"
        SDL_LIBRARY_FILE_PATH="$LIB_DIR/$SDL_LIBRARY_FILE_NAME"
    elif [[ "$TARGET_BUILD_OS" == "apple" ]]; then
        SDL_LIBRARY_FILE_NAME="libSDL2-2.0.dylib"
        SDL_LIBRARY_FILE_PATH="$LIB_DIR/$SDL_LIBRARY_FILE_NAME"
    fi

    if [[ ! -z "$SDL_INCLUDE_DIRECTORY_PATH" ]]; then
        if [ ! -d "$SDL_INCLUDE_DIRECTORY_PATH" ]; then
            echo "Custom SDL include path '$SDL_INCLUDE_DIRECTORY_PATH' does not exist!"
        else
            echo "Using custom SDL include path: $SDL_INCLUDE_DIRECTORY_PATH"
        fi
    elif [ ! -d "$DIR/SDL" ]; then
        git clone https://github.com/libsdl-org/SDL $DIR/SDL
        SDL_INCLUDE_DIRECTORY_PATH="$DIR/SDL/include"
        echo "Using SDL include path from clone: $SDL_INCLUDE_DIRECTORY_PATH"
    else
        cd $DIR/SDL
        git pull
        cd $DIR
        SDL_INCLUDE_DIRECTORY_PATH="$DIR/SDL/include"
        echo "Using SDL include path from clone: $SDL_INCLUDE_DIRECTORY_PATH"
    fi

    if [ ! -f "$SDL_LIBRARY_FILE_PATH" ]; then
        SDL_BUILD_DIR="$DIR/cmake-build-release-sdl"
        cmake $CMAKE_TOOLCHAIN_ARGS -S $DIR/SDL -B $SDL_BUILD_DIR -DSDL_STATIC=OFF -DSDL_TEST=OFF
        cmake --build $SDL_BUILD_DIR --config Release $CMAKE_ARCH_ARGS

        if [[ "$TARGET_BUILD_OS" == "linux" ]]; then
            SDL_LIBRARY_FILE_PATH_BUILD="$(readlink -f $SDL_BUILD_DIR/$SDL_LIBRARY_FILE_NAME)"
        elif [[ "$TARGET_BUILD_OS" == "apple" ]]; then
            SDL_LIBRARY_FILE_PATH_BUILD="$SDL_BUILD_DIR/$SDL_LIBRARY_FILE_NAME"
        elif [[ "$TARGET_BUILD_OS" == "microsoft" ]]; then
            SDL_LIBRARY_FILE_PATH_BUILD="$SDL_BUILD_DIR/$SDL_LIBRARY_FILE_NAME"
        fi

        if [[ ! -f "$SDL_LIBRARY_FILE_PATH_BUILD" ]]; then
            echo "The file '$SDL_LIBRARY_FILE_PATH_BUILD' does not exist!"
            exit 1
        fi

        mv "$SDL_LIBRARY_FILE_PATH_BUILD" "$SDL_LIBRARY_FILE_PATH"
        exit_if_last_command_failed
        echo "Copied '$SDL_LIBRARY_FILE_PATH_BUILD' to '$SDL_LIBRARY_FILE_PATH'"

        rm -rf $SDL_BUILD_DIR
        exit_if_last_command_failed
    fi

    echo "Building SDL complete!"
}

function build_fna3d() {
    echo "Building FNA3D..."
    FNA3D_BUILD_DIR="$DIR/cmake-build-release-fna3d"
    cmake $CMAKE_TOOLCHAIN_ARGS -S $DIR/ext/FNA3D -B $FNA3D_BUILD_DIR -DSDL2_INCLUDE_DIRS="$SDL_INCLUDE_DIRECTORY_PATH" -DSDL2_LIBRARIES="$SDL_LIBRARY_FILE_PATH"
    cmake --build $FNA3D_BUILD_DIR --config Release $CMAKE_ARCH_ARGS

    if [[ "$TARGET_BUILD_OS" == "linux" ]]; then
        FNA3D_LIBRARY_FILENAME="libFNA3D.so"
        FNA3D_LIBRARY_FILE_PATH_BUILD="$(readlink -f $FNA3D_BUILD_DIR/$FNA3D_LIBRARY_FILENAME)"
    elif [[ "$TARGET_BUILD_OS" == "apple" ]]; then
        FNA3D_LIBRARY_FILENAME="libFNA3D.dylib"
        FNA3D_LIBRARY_FILE_PATH_BUILD="$(perl -MCwd -e 'print Cwd::abs_path shift' $FNA3D_BUILD_DIR/$FNA3D_LIBRARY_FILENAME)"
    elif [[ "$TARGET_BUILD_OS" == "microsoft" ]]; then
        FNA3D_LIBRARY_FILENAME="FNA3D.dll"
        FNA3D_LIBRARY_FILE_PATH_BUILD="$FNA3D_BUILD_DIR/$FNA3D_LIBRARY_FILENAME"
    fi
    FNA3D_LIBRARY_FILE_PATH="$LIB_DIR/$FNA3D_LIBRARY_FILENAME"

    if [[ ! -f "$FNA3D_LIBRARY_FILE_PATH_BUILD" ]]; then
        echo "The file '$FNA3D_LIBRARY_FILE_PATH_BUILD' does not exist!"
        exit 1
    fi

    if [[ "$TARGET_BUILD_OS" == "apple" ]]; then
        install_name_tool -delete_rpath "$LIB_DIR" "$FNA3D_LIBRARY_FILE_PATH_BUILD"
    fi

    mv "$FNA3D_LIBRARY_FILE_PATH_BUILD" "$FNA3D_LIBRARY_FILE_PATH"
    exit_if_last_command_failed
    echo "Copied '$FNA3D_LIBRARY_FILE_PATH_BUILD' to '$FNA3D_LIBRARY_FILE_PATH'"

    rm -rf $FNA3D_BUILD_DIR
    exit_if_last_command_failed
    echo "Building FNA3D finished!"
}

build_sdl
build_fna3d
ls -d "$LIB_DIR"/*

echo "Finished '$0'!"