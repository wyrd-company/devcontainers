ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE} AS dart
USER root
RUN id vscode >/dev/null 2>&1 || useradd -m -s /bin/bash vscode
COPY src/features/dart /tmp/dart-feature
ARG DART_VERSION=latest
RUN cd /tmp/dart-feature && VERSION="$DART_VERSION" _REMOTE_USER=vscode bash install.sh
COPY test/features/dart /tmp/dart-tests
# The same checks serve both the official Feature test runner and this image.
RUN printf 'check() { echo "$1"; shift; "$@"; }\nreportResults() { :; }\n' > /usr/local/bin/dev-container-features-test-lib
USER vscode
RUN bash /tmp/dart-tests/test.sh

FROM dart AS flutter
USER root
COPY src/features/flutter /tmp/flutter-feature
ARG FLUTTER_VERSION=latest
ARG ANDROID_SDK=false
RUN cd /tmp/flutter-feature && VERSION="$FLUTTER_VERSION" ANDROIDSDK="$ANDROID_SDK" _REMOTE_USER=vscode bash install.sh
ENV FLUTTER_HOME=/opt/flutter ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}
ENV PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig:/usr/lib/pkgconfig
ENV LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
COPY test/features/flutter /tmp/flutter-tests
USER vscode
RUN test "$(stat -c %U /opt/flutter)" = vscode && test "$(stat -c %U /opt/dart-sdk)" = vscode
RUN bash /tmp/flutter-tests/test.sh
RUN if [ "$ANDROID_SDK" = true ]; then sdkmanager --list_installed | grep 'build-tools;35.0.0'; fi
