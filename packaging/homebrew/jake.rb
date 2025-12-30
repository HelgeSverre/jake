# Homebrew formula for jake
# To install locally: brew install --build-from-source ./packaging/homebrew/jake.rb
# To tap: brew tap HelgeSverre/jake && brew install jake

class Jake < Formula
  desc "Modern command runner with Make's dependency tracking and Just's UX"
  homepage "https://github.com/HelgeSverre/jake"
  url "https://github.com/HelgeSverre/jake/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256" # Update with: shasum -a 256 v0.2.0.tar.gz
  license "MIT"
  head "https://github.com/HelgeSverre/jake.git", branch: "main"

  depends_on "zig" => :build

  def install
    # Build with release optimizations
    system "zig", "build", "-Doptimize=ReleaseSafe", "--prefix", prefix

    # Generate shell completions (once implemented)
    # generate_completions_from_executable(bin/"jake", "--completions")
  end

  test do
    # Test version output
    assert_match version.to_s, shell_output("#{bin}/jake --version")

    # Test with a simple Jakefile
    (testpath/"Jakefile").write <<~EOS
      task hello:
          echo "Hello from jake!"
    EOS

    output = shell_output("#{bin}/jake hello")
    assert_match "Hello from jake!", output
  end
end
