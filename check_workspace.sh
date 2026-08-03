if git diff --cached --name-only |
   grep -E '^workspace/(aionnich|astra-sim-upstream)(/|$)'; then
    echo "ERROR: external repositories are still staged"
    exit 1
else
    echo "External repositories are excluded"
fi
