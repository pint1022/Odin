cat >> .gitignore <<'EOF'

# External source repositories
/workspace/aionnich/
/workspace/astra-sim-upstream/
EOF

git restore --staged workspace/aionnich workspace/astra-sim-upstream
