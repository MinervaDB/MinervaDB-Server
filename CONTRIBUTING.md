# Contributing to MinervaDB Server for ClickHouse

Thank you for your interest in contributing! This guide covers how to contribute documentation, configurations, tools, and bug reports.

---

## Ways to Contribute

- **Documentation**: Fix errors, add runbooks, improve examples
- **Configurations**: Production-tested config templates and tuning
- **Scripts/Tools**: Health check scripts, diagnostic automation  
- **Bug Reports**: Incorrect docs, broken examples, outdated content

---

## Getting Started

### Fork and Clone

```bash
git clone https://github.com/YOUR_USERNAME/MinervaDB-Server.git
cd MinervaDB-Server
git remote add upstream https://github.com/MinervaDB/MinervaDB-Server.git
```

### Test Configuration Changes

```bash
# Spin up ClickHouse locally for testing
docker run -d --name ch-test -p 8123:8123 -p 9000:9000 \
  -v $(pwd)/configs/production:/etc/clickhouse-server/config.d \
    clickhouse/clickhouse-server:latest

    # Verify server started without errors
    docker exec ch-test clickhouse-client -q "SELECT version()"
    docker logs ch-test 2>&1 | grep -i error
    ```

    ---

    ## Branching and Commits

    ### Branch Naming

    ```
    feature/add-tiered-storage-config
    fix/kafka-consumer-example
    docs/update-performance-indexing
    chore/update-version-references
    ```

    ### Commit Message Format

    ```
    <type>(<scope>): <description>
    ```

    Types: `feat`, `fix`, `docs`, `chore`, `refactor`

    Examples:
    ```
    docs(performance): add ZSTD dictionary compression example
    feat(configs): add Kubernetes StatefulSet for 3-node HA cluster
    fix(observability): correct Prometheus disk space alert threshold
    ```

    ---

    ## Pull Request Requirements

    Before submitting a PR, please ensure:

    - Documentation is accurate and tested
    - SQL queries have been validated against a real ClickHouse instance
    - Configuration examples have been tested in Docker or a real cluster
    - No credentials, passwords, or API keys included
    - Links are valid

    PR description should include:
    1. **What changed** and **why**
    2. **How you tested** the changes
    3. **ClickHouse version** tested against

    ---

    ## Documentation Standards

    ### Code Block Language Tags

    Always specify language for code blocks:
    - ` ```sql ` for SQL queries
    - ` ```bash ` for shell commands
    - ` ```xml ` for ClickHouse configuration
    - ` ```yaml ` for YAML files
    - ` ```python ` for Python code

    ### SQL Style Guide

    ```sql
    -- Use readable formatting with aligned columns
    SELECT
        database,
            table,
                formatReadableSize(sum(bytes_on_disk)) AS size,
                    count() AS part_count
                    FROM system.parts
                    WHERE active = 1
                      AND database NOT IN ('system', 'information_schema')
                      GROUP BY database, table
                      ORDER BY sum(bytes_on_disk) DESC
                      LIMIT 20;
                      ```

                      ### XML Configuration Style

                      ```xml
                      <!-- Always include comments explaining each setting and its impact -->
                      <merge_tree>
                        <!-- Maximum part size to merge at full disk. Default: 150GB -->
                          <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
                          </merge_tree>
                          ```

                          ---

                          ## Reporting Issues

                          ### Bug Reports

                          Please include:
                          - ClickHouse version (`SELECT version()`)
                          - Operating system and hardware specs
                          - Minimal reproducible example
                          - Error messages from `system.query_log` or server logs
                          - Expected vs actual behavior

                          ### Feature Requests

                          Please describe:
                          - The use case this would address
                          - Your proposed solution
                          - Any alternatives you've considered

                          ---

                          ## Community

                          - **GitHub Issues**: https://github.com/MinervaDB/MinervaDB-Server/issues
                          - **GitHub Discussions**: https://github.com/MinervaDB/MinervaDB-Server/discussions
                          - **MinervaDB**: https://minervadb.xyz
                          - **Upstream ClickHouse**: https://github.com/ClickHouse/ClickHouse

                          ---

                          ## License

                          Contributions are licensed under [Apache 2.0](LICENSE).
