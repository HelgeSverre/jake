package tree_sitter_jake_test

import (
	"testing"

	tree_sitter "github.com/smacker/go-tree-sitter"
	"github.com/tree-sitter/tree-sitter-jake"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_jake.Language())
	if language == nil {
		t.Errorf("Error loading Jake grammar")
	}
}
