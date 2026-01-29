-- RBAC setup for altinity-expert test user
-- Requires a user with CREATE USER and GRANT privileges.
-- Uses an empty password by default; change before applying if desired.

CREATE USER IF NOT EXISTS `altinity-expert`
IDENTIFIED WITH plaintext_password BY '';

-- Core privileges for test runner
GRANT CREATE DATABASE, DROP DATABASE ON *.* TO `altinity-expert`;
GRANT SELECT ON system.* TO `altinity-expert`;
GRANT SYSTEM FLUSH LOGS, SYSTEM START MERGES, SYSTEM STOP MERGES, SYSTEM RELOAD DICTIONARY ON *.* TO `altinity-expert`;
GRANT dictGet ON *.* TO `altinity-expert`;

-- Database-level privileges for skill tests
GRANT SELECT, INSERT, ALTER, CREATE TABLE, DROP TABLE, TRUNCATE, OPTIMIZE,
      CREATE DICTIONARY, DROP DICTIONARY
ON altinity*.* TO `altinity-expert`;

GRANT SELECT, INSERT, ALTER, CREATE TABLE, DROP TABLE, TRUNCATE, OPTIMIZE,
      CREATE DICTIONARY, DROP DICTIONARY
ON test*.* TO `altinity-expert`;
