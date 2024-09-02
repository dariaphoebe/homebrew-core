class Wangle < Formula
  desc "Modular, composable client/server abstractions framework"
  homepage "https://github.com/facebook/wangle"
  url "https://github.com/facebook/wangle/archive/refs/tags/v2024.09.02.00.tar.gz"
  sha256 "580eef155a4579cdf7ab41034043f7aeb9600d44fd8ef8785038c11acdd3bf4f"
  license "Apache-2.0"
  head "https://github.com/facebook/wangle.git", branch: "main"

  bottle do
    sha256 cellar: :any,                 arm64_sonoma:   "a62a601beda509c0e8843e10eaab7e466cba494f9e4f82a09d9d7174c9d4518d"
    sha256 cellar: :any,                 arm64_ventura:  "635f72691a8730a993a49582fc6f57826ebded5060e24e1146ea7c3a526cd877"
    sha256 cellar: :any,                 arm64_monterey: "4c13c7c22ecb14a9d283fb8843c8f37f0fd6481f6dbad6a76583a0bdf56bf82e"
    sha256 cellar: :any,                 sonoma:         "9d049d7db9d2a16a3e9598e85820d03774e73f154f5da5feaf9048a6f5e4feec"
    sha256 cellar: :any,                 ventura:        "7a09271c2711aae5d00cb63dd0f48c0fb5810f3f88b50533a079ec1522b90a84"
    sha256 cellar: :any,                 monterey:       "fb5744b569f23a2b81fdd4f5d76273cb0b59ef637be7a7a64952f5f2ffb73f06"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "1c3392ddadb2cf1a003bd3844b4b012de5c01dcf6486db0337e7c3e1f5ace926"
  end

  depends_on "cmake" => [:build, :test]
  depends_on "double-conversion"
  depends_on "fizz"
  depends_on "fmt"
  depends_on "folly"
  depends_on "gflags"
  depends_on "glog"
  depends_on "libevent"
  depends_on "lz4"
  depends_on "openssl@3"
  depends_on "zstd"
  uses_from_macos "bzip2"

  fails_with gcc: "5"

  def install
    args = ["-DBUILD_TESTS=OFF"]
    # Prevent indirect linkage with boost, libsodium, snappy and xz
    linker_flags = %w[-dead_strip_dylibs]
    args << "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,#{linker_flags.join(",")}" if OS.mac?

    system "cmake", "-S", "wangle", "-B", "build/shared", "-DBUILD_SHARED_LIBS=ON", *args, *std_cmake_args
    system "cmake", "--build", "build/shared"
    system "cmake", "--install", "build/shared"

    system "cmake", "-S", "wangle", "-B", "build/static", "-DBUILD_SHARED_LIBS=OFF", *args, *std_cmake_args
    system "cmake", "--build", "build/static"
    lib.install "build/static/lib/libwangle.a"

    pkgshare.install Dir["wangle/example/echo/*.cpp"]
  end

  test do
    # libsodium has no CMake file but fizz runs `find_dependency(Sodium)` so fetch a copy from mvfst
    resource "FindSodium.cmake" do
      url "https://raw.githubusercontent.com/facebook/mvfst/v2024.09.02.00/cmake/FindSodium.cmake"
      sha256 "39710ab4525cf7538a66163232dd828af121672da820e1c4809ee704011f4224"
    end
    (testpath/"cmake").install resource("FindSodium.cmake")

    (testpath/"CMakeLists.txt").write <<~EOS
      cmake_minimum_required(VERSION 3.5)
      project(Echo LANGUAGES CXX)
      set(CMAKE_CXX_STANDARD 17)

      find_package(gflags REQUIRED)
      find_package(folly CONFIG REQUIRED)
      find_package(fizz CONFIG REQUIRED)
      find_package(wangle CONFIG REQUIRED)

      add_executable(EchoClient #{pkgshare}/EchoClient.cpp)
      target_link_libraries(EchoClient wangle::wangle)
      add_executable(EchoServer #{pkgshare}/EchoServer.cpp)
      target_link_libraries(EchoServer wangle::wangle)
    EOS

    ENV.delete "CPATH"
    system "cmake", ".", "-DCMAKE_MODULE_PATH=#{testpath}/cmake", "-Wno-dev"
    system "cmake", "--build", "."

    port = free_port
    fork { exec testpath/"EchoServer", "-port", port.to_s }
    sleep 10

    require "pty"
    output = ""
    PTY.spawn(testpath/"EchoClient", "-port", port.to_s) do |r, w, pid|
      w.write "Hello from Homebrew!\nAnother test line.\n"
      sleep 20
      Process.kill "TERM", pid
      begin
        r.each_line { |line| output += line }
      rescue Errno::EIO
        # GNU/Linux raises EIO when read is done on closed pty
      end
    end
    assert_match("Hello from Homebrew!", output)
    assert_match("Another test line.", output)
  end
end
