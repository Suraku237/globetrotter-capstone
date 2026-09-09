from fastapi import HTTPException


def message_page(messages: list, limit: int | None, before: str | None) -> list:
    if before is not None:
        index = next((i for i, message in enumerate(messages) if message["id"] == before), None)
        if index is None:
            raise HTTPException(status_code=404, detail="Message cursor not found")
        messages = messages[:index]
    # Preserve the historical full-list default for existing app versions.
    return messages[-limit:] if limit is not None else messages
