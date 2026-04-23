---
name: gb-pipefy
description: "Interact with Pipefy GraphQL API: query pipes, read/create/update/move cards, check status. Use when the user mentions Pipefy, cards, pipes, or phases."
user-invocable: true
---

# Pipefy API

> Use `/pipefy` to interact with the Pipefy GraphQL API.

## Authentication

- **Endpoint:** `https://api.pipefy.com/graphql`
- **Token:** `__PIPEFY_TOKEN__`

All requests use this curl pattern:

```bash
curl -s -X POST https://api.pipefy.com/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer __PIPEFY_TOKEN__" \
  -d '{"query": "<GRAPHQL_QUERY>"}'
```

Use `jq` to parse responses.

## Queries

### Current user

```graphql
{ me { id name email } }
```

### Pipe structure (phases, fields, labels)

```graphql
{
  pipe(id: PIPE_ID) {
    id name uuid cards_count
    phases {
      id name
      fields { id internal_id label index_name field_type required }
    }
    start_form_fields { id internal_id label index_name field_type }
    labels { id name color }
    members { id name email }
  }
}
```

### Single card

```graphql
{
  card(id: CARD_ID) {
    id title done
    pipe { id name }
    current_phase { id name }
    fields { id name value native_value filled_at }
    assignees { name email }
    attachments { url path }
    created_at updated_at
  }
}
```

### List cards in a pipe (paginated)

```graphql
{
  cards(pipe_id: PIPE_ID, first: 20) {
    edges {
      node {
        id title
        current_phase { id name }
        fields {
          id value native_value
          field { id label internal_id index_name }
        }
        assignees { id name email }
      }
    }
    pageInfo { hasNextPage endCursor }
  }
}
```

Pagination: use `first`/`after` or `last`/`before` with cursors from `pageInfo`.

### Cards in a specific phase

```graphql
{
  phase(id: PHASE_ID) {
    id name
    cards(first: 20) {
      edges { node { id title current_phase { id } } }
    }
    fields { id label internal_id field_type }
  }
}
```

### Card phase history

```graphql
{
  card(id: CARD_ID) {
    id title
    current_phase { id name }
    done
  }
}
```

## Mutations

### Create card

```graphql
mutation {
  createCard(input: {
    pipe_id: PIPE_ID
    title: "Card title"
    phase_id: PHASE_ID
    assignee_ids: ["USER_ID"]
    fields_attributes: [
      { field_id: "FIELD_UUID", field_value: "value" }
    ]
  }) {
    card { id title current_phase { id name } }
  }
}
```

- `pipe_id` required, all others optional
- `fields_attributes` uses field UUIDs (get from pipe structure query)

### Update card fields (batch, up to 30 fields)

```graphql
mutation {
  updateFieldsValues(input: {
    nodeId: CARD_ID
    values: [
      { fieldId: "FIELD_UUID", value: "new value" }
      { fieldId: "FIELD_UUID", value: ["id1", "id2"], operation: SET }
    ]
  }) {
    success
    updatedNode { ... on Card { id fields { id name value } } }
  }
}
```

Operations: `SET` (default), `ADD`, `REMOVE`, `REPLACE`.

### Update single field (legacy)

```graphql
mutation {
  updateCardField(input: {
    card_id: CARD_ID
    field_id: "FIELD_UUID"
    new_value: "updated value"
  }) {
    card { id fields { id name value } }
  }
}
```

### Move card to phase

```graphql
mutation {
  moveCardToPhase(input: {
    card_id: CARD_ID
    destination_phase_id: PHASE_ID
  }) {
    card { id title current_phase { id name } }
  }
}
```

### Delete card

```graphql
mutation {
  deleteCard(input: { id: CARD_ID }) {
    success
  }
}
```

## Workflow

1. **Discover** — query pipe structure to get phase IDs and field UUIDs
2. **Query** — list or fetch cards with the IDs from step 1
3. **Act** — create, update, move, or delete cards as needed
4. **Confirm** — re-query to verify the mutation succeeded

## Rules

- **ALWAYS** query pipe structure first to get correct field UUIDs and phase IDs — never guess them
- **ALWAYS** use `jq` to parse and format API responses for readability
- **ALWAYS** prefer `updateFieldsValues` over `updateCardField` for multi-field updates
- **NEVER** expose the API token in output to the user
- **NEVER** delete cards without explicit user confirmation
- If a query returns paginated results, inform the user and offer to fetch more
- On error, check the response for `errors[].message` and report clearly
