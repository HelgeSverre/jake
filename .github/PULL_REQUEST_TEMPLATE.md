## Summary

<!-- Brief description of what this PR does -->

## Type of Change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)
- [ ] Performance improvement
- [ ] CI/CD changes

## Related Issues

<!-- Link any related issues: Fixes #123, Relates to #456 -->

## Testing

Run the full test suite before submitting:

```bash
jake ci          # Runs lint + test + build
jake e2e         # End-to-end tests
```

<details>
<summary>Alternative: raw commands if jake isn't installed</summary>

```bash
zig fmt --check src/                          # Lint
zig build test --summary all                  # Unit tests
cd tests/e2e && ../../zig-out/bin/jake test-all  # E2E tests
```

</details>

- [ ] I have tested this change locally
- [ ] All tests pass (`jake ci`)
- [ ] E2E tests pass (`jake e2e`)
- [ ] I have added tests for new functionality (if applicable)

## Documentation

If adding/modifying user-facing features, update the relevant docs (see CLAUDE.md for full checklist):

- [ ] `docs/SYNTAX.md` - Syntax reference
- [ ] `docs/TUTORIAL.md` - Usage examples
- [ ] `site/src/content/docs/` - Website documentation
- [ ] N/A - This change doesn't affect user-facing behavior

## Checklist

- [ ] My code follows the project's style guidelines (`jake lint` passes)
- [ ] I have performed a self-review of my code
- [ ] I have added comments where the logic isn't self-evident
- [ ] My changes generate no new warnings

## Additional Notes

<!-- Any additional context, screenshots, or performance benchmarks -->
