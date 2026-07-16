from __future__ import annotations

import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import text
from sqlalchemy import pool
from sqlalchemy.ext.asyncio import async_engine_from_config


config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)
config.set_main_option("sqlalchemy.url", os.getenv("DATABASE_URL", config.get_main_option("sqlalchemy.url")))


def configure_context(*, connection=None, url=None) -> None:
    context.configure(
        connection=connection,
        url=url,
        literal_binds=url is not None,
        version_table="discovery_alembic_version",
        version_table_schema="discovery",
        include_schemas=True,
    )


def run_migrations_offline() -> None:
    configure_context(url=config.get_main_option("sqlalchemy.url"))
    # Keep generated recovery SQL executable too: Alembic emits the version
    # table before the first revision's CREATE SCHEMA statement.
    context.execute("CREATE SCHEMA IF NOT EXISTS discovery")
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    # Alembic creates its version table before running revision 0001. Bootstrap
    # the isolated namespace first, so it never falls back to context's table.
    # The async SQLAlchemy connection otherwise closes with its implicit
    # transaction uncommitted, making a seemingly successful first upgrade
    # disappear after the process exits.
    with connection.begin():
        connection.execute(text("CREATE SCHEMA IF NOT EXISTS discovery"))
        configure_context(connection=connection)
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_async_migrations())
