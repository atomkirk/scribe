let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.MentionInput = {
    mounted() {
        this.mentionStart = null
        this.lastQuery = null
        this.mentionActive = false
        
        // Handle input events to detect @ mentions
        this.el.addEventListener("input", (e) => {
            this.handleInput(e)
        })
        
        // Handle keydown for navigation
        this.el.addEventListener("keydown", (e) => {
            this.handleKeydown(e)
        })
        
        // Handle blur to close mention dropdown (with delay for click handling)
        this.el.addEventListener("blur", (e) => {
            // Delay to allow click events on dropdown to fire first
            setTimeout(() => {
                if (this.mentionActive) {
                    this.pushEvent("close_mention", {})
                    this.mentionActive = false
                }
            }, 200)
        })
        
        // Listen for contact selection - insert the mention inline
        this.handleEvent("insert_mention", ({ contact_name, contact_id }) => {
            this.insertMention(contact_name, contact_id)
        })
        
        // Listen for focus request
        this.handleEvent("focus_input", () => {
            this.el.focus()
        })
    },
    
    insertMention(contactName, contactId) {
        const value = this.el.value
        const cursorPos = this.el.selectionStart
        
        if (this.mentionStart !== null) {
            // Replace @query with @ContactName
            const beforeMention = value.slice(0, this.mentionStart)
            const afterCursor = value.slice(cursorPos)
            
            // Insert the mention with a trailing space
            const mentionText = `@${contactName} `
            const newValue = beforeMention + mentionText + afterCursor
            
            // Update the input value
            this.el.value = newValue
            
            // Move cursor to after the mention
            const newCursorPos = this.mentionStart + mentionText.length
            this.el.setSelectionRange(newCursorPos, newCursorPos)
            
            // Trigger input event so LiveView gets the update
            this.el.dispatchEvent(new Event('input', { bubbles: true }))
            
            // Push the updated value to the server
            this.pushEvent("update_input_value", { value: newValue })
        }
        
        // Reset mention state
        this.mentionStart = null
        this.lastQuery = null
        this.mentionActive = false
        
        // Keep focus on input
        this.el.focus()
    },
    
    handleInput(e) {
        const value = this.el.value
        const cursorPos = this.el.selectionStart
        
        // Look for @ pattern before cursor (not followed by a space, which would mean it's a completed mention)
        const textBeforeCursor = value.slice(0, cursorPos)
        const match = textBeforeCursor.match(/@(\w*)$/)
        
        if (match) {
            // Found @ mention pattern
            this.mentionStart = cursorPos - match[1].length - 1 // Position of @
            const query = match[1]
            this.mentionActive = true
            
            // Only search if query changed
            if (query !== this.lastQuery) {
                this.lastQuery = query
                this.pushEvent("mention_search", { query: query })
            }
        } else {
            // No @ pattern, close mention if it was open
            if (this.mentionActive) {
                this.mentionStart = null
                this.lastQuery = null
                this.mentionActive = false
                this.pushEvent("close_mention", {})
            }
        }
    },
    
    handleKeydown(e) {
        // Check if mention dropdown is active
        if (!this.mentionActive) return
        
        const dropdown = document.getElementById("mention-dropdown")
        if (!dropdown) return
        
        switch (e.key) {
            case "ArrowDown":
                e.preventDefault()
                this.pushEvent("mention_navigate", { direction: "down" })
                break
            case "ArrowUp":
                e.preventDefault()
                this.pushEvent("mention_navigate", { direction: "up" })
                break
            case "Enter":
                // If mention is active, select the highlighted contact
                e.preventDefault()
                e.stopPropagation()
                this.pushEvent("mention_select_current", {})
                break
            case "Escape":
                e.preventDefault()
                this.mentionStart = null
                this.lastQuery = null
                this.mentionActive = false
                this.pushEvent("close_mention", {})
                break
            case "Tab":
                // Tab also selects current mention
                e.preventDefault()
                this.pushEvent("mention_select_current", {})
                break
        }
    }
}

Hooks.ScrollToBottom = {
    mounted() {
        this.scrollToBottom()
    },
    updated() {
        this.scrollToBottom()
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

export default Hooks