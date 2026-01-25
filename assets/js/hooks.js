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
        this.mentionRange = null // Store the range where @ was typed
        
        // Initialize submit button state
        this.updateSubmitButtonState()
        
        // Handle input events to detect @ mentions
        this.el.addEventListener("input", (e) => {
            this.handleInput(e)
            this.updateHiddenInput()
            this.updateSubmitButtonState()
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
        
        // Handle paste - strip HTML and keep only text
        this.el.addEventListener("paste", (e) => {
            e.preventDefault()
            const text = e.clipboardData.getData("text/plain")
            document.execCommand("insertText", false, text)
        })
        
        // Intercept form submission to extract message
        const form = this.el.closest("form")
        if (form) {
            form.addEventListener("submit", (e) => {
                this.updateHiddenInput()
            })
        }
        
        // Listen for contact selection - insert the mention chip
        this.handleEvent("insert_mention", ({ contact_name, contact_id, photo_url, firstname, lastname }) => {
            this.insertMention(contact_name, contact_id, photo_url, firstname, lastname)
        })
        
        // Listen for focus request
        this.handleEvent("focus_input", () => {
            this.el.focus()
        })
        
        // Listen for clear input (after message sent)
        this.handleEvent("clear_input", () => {
            this.el.innerHTML = ""
            this.updateHiddenInput()
            this.updateSubmitButtonState()
        })
    },
    
    updated() {
        // Re-sync button state when LiveView updates (e.g., loading state changes)
        this.updateSubmitButtonState()
    },
    
    // Get initials from firstname and lastname
    getInitials(firstname, lastname, displayName) {
        if (firstname || lastname) {
            const f = firstname ? firstname.charAt(0) : ""
            const l = lastname ? lastname.charAt(0) : ""
            return (f + l).toUpperCase()
        }
        // Fallback: get from display name
        const parts = (displayName || "").split(/\s+/)
        return parts.slice(0, 2).map(p => p.charAt(0)).join("").toUpperCase()
    },
    
    // Build the chip HTML
    buildChipHtml(contactName, contactId, photoUrl, firstname, lastname) {
        const initials = this.getInitials(firstname, lastname, contactName)
        const escapedName = contactName.replace(/</g, "&lt;").replace(/>/g, "&gt;")
        
        // Always show initials
        const avatarHtml = `<span class="w-4 h-4 rounded-full bg-[#C6CCD1] flex items-center justify-center text-[8px] font-semibold text-[#0C1216] mr-1.5 flex-shrink-0">${initials}</span>`
        
        return `<span contenteditable="false" data-mention="true" data-contact-id="${contactId}" data-contact-name="${escapedName}" class="inline-flex items-center bg-white text-gray-900 rounded-full pl-0.5 pr-2 py-0.5 text-sm font-medium border border-gray-200">${avatarHtml}${escapedName}</span>`
    },
    
    insertMention(contactName, contactId, photoUrl, firstname, lastname) {
        if (this.mentionRange) {
            const selection = window.getSelection()
            
            // Restore the saved range and delete the @query text
            selection.removeAllRanges()
            selection.addRange(this.mentionRange)
            
            // Delete from @ to current position (the @query text)
            this.mentionRange.deleteContents()
            
            // Create the chip element
            const chipHtml = this.buildChipHtml(contactName, contactId, photoUrl, firstname, lastname)
            const template = document.createElement("template")
            template.innerHTML = chipHtml
            const chipNode = template.content.firstChild
            
            // Insert the chip
            this.mentionRange.insertNode(chipNode)
            
            // Add a space after the chip and move cursor there
            const space = document.createTextNode("\u00A0") // non-breaking space
            chipNode.after(space)
            
            // Move cursor after the space
            const newRange = document.createRange()
            newRange.setStartAfter(space)
            newRange.setEndAfter(space)
            selection.removeAllRanges()
            selection.addRange(newRange)
        }
        
        // Reset mention state
        this.mentionStart = null
        this.mentionRange = null
        this.lastQuery = null
        this.mentionActive = false
        
        // Update hidden input
        this.updateHiddenInput()
        
        // Keep focus on input
        this.el.focus()
    },
    
    // Get text before cursor in contenteditable
    getTextBeforeCursor() {
        const selection = window.getSelection()
        if (!selection.rangeCount) return ""
        
        const range = selection.getRangeAt(0)
        const preCaretRange = range.cloneRange()
        preCaretRange.selectNodeContents(this.el)
        preCaretRange.setEnd(range.startContainer, range.startOffset)
        
        // Get text content, but we need to handle mention chips specially
        // Walk through nodes to build text
        let text = ""
        const walker = document.createTreeWalker(
            this.el,
            NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
            null,
            false
        )
        
        while (walker.nextNode()) {
            const node = walker.currentNode
            
            // Check if we've passed the cursor position
            if (preCaretRange.comparePoint(node, 0) > 0) break
            
            if (node.nodeType === Node.TEXT_NODE) {
                // Check if this text node is fully before cursor
                if (node === range.startContainer) {
                    text += node.textContent.substring(0, range.startOffset)
                } else if (preCaretRange.comparePoint(node, node.length) <= 0) {
                    text += node.textContent
                }
            } else if (node.nodeType === Node.ELEMENT_NODE && node.dataset.mention === "true") {
                // This is a mention chip - add as @name
                text += `@${node.dataset.contactName} `
            }
        }
        
        return text
    },
    
    handleInput(e) {
        const selection = window.getSelection()
        if (!selection.rangeCount) return
        
        // Get text content before cursor for @ detection
        const textBeforeCursor = this.getTextBeforeCursor()
        const match = textBeforeCursor.match(/@(\w*)$/)
        
        if (match) {
            // Found @ mention pattern
            const query = match[1]
            this.mentionActive = true
            
            // Save the range from @ to cursor for later replacement
            const range = selection.getRangeAt(0).cloneRange()
            
            // Calculate how far back to go to reach @
            const charsToGoBack = match[0].length
            
            // Create a range that starts at @ symbol
            const startRange = range.cloneRange()
            let charsToMove = charsToGoBack
            let node = range.startContainer
            let offset = range.startOffset
            
            // Walk backwards to find the @ symbol
            while (charsToMove > 0 && node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    if (offset >= charsToMove) {
                        offset -= charsToMove
                        charsToMove = 0
                    } else {
                        charsToMove -= offset
                        // Move to previous sibling or parent's previous sibling
                        const prev = node.previousSibling
                        if (prev) {
                            node = prev
                            if (node.nodeType === Node.TEXT_NODE) {
                                offset = node.length
                            } else {
                                offset = 0
                            }
                        } else {
                            break
                        }
                    }
                } else {
                    break
                }
            }
            
            // Set the range from @ to cursor
            startRange.setStart(node, offset)
            startRange.setEnd(range.startContainer, range.startOffset)
            this.mentionRange = startRange
            
            // Only search if query changed
            if (query !== this.lastQuery) {
                this.lastQuery = query
                this.pushEvent("mention_search", { query: query })
            }
        } else {
            // No @ pattern, close mention if it was open
            if (this.mentionActive) {
                this.mentionRange = null
                this.lastQuery = null
                this.mentionActive = false
                this.pushEvent("close_mention", {})
            }
        }
    },
    
    // Extract message text from contenteditable (with @mentions)
    extractMessage() {
        let message = ""
        
        const walkNodes = (node) => {
            if (node.nodeType === Node.TEXT_NODE) {
                // Replace non-breaking spaces with regular spaces
                message += node.textContent.replace(/\u00A0/g, " ")
            } else if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.dataset && node.dataset.mention === "true") {
                    // This is a mention chip - add as @name
                    message += `@${node.dataset.contactName}`
                } else if (node.tagName === "BR") {
                    message += "\n"
                } else {
                    // Recurse into children
                    for (const child of node.childNodes) {
                        walkNodes(child)
                    }
                }
            }
        }
        
        for (const child of this.el.childNodes) {
            walkNodes(child)
        }
        
        return message.trim()
    },
    
    // Update the hidden input with extracted message
    updateHiddenInput() {
        const hiddenInput = document.getElementById("message-value")
        if (hiddenInput) {
            hiddenInput.value = this.extractMessage()
        }
    },
    
    // Update submit button disabled state based on input content
    updateSubmitButtonState() {
        const form = this.el.closest("form")
        if (!form) return
        
        const submitBtn = form.querySelector('button[type="submit"]')
        if (!submitBtn) return
        
        const message = this.extractMessage()
        const isLoading = submitBtn.dataset.loading === "true"
        
        if (message.length > 0 && !isLoading) {
            submitBtn.disabled = false
        } else {
            submitBtn.disabled = true
        }
    },
    
    handleKeydown(e) {
        // Handle Enter for form submission when mention is not active
        if (e.key === "Enter" && !e.shiftKey && !this.mentionActive) {
            e.preventDefault()
            this.updateHiddenInput()
            const form = this.el.closest("form")
            if (form) {
                form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
            }
            return
        }
        
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
                this.mentionRange = null
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

Hooks.LocalTime = {
    mounted() {
        this.updateTime()
    },
    updated() {
        this.updateTime()
    },
    updateTime() {
        const utcTime = this.el.dataset.utc
        if (!utcTime) return
        
        const date = new Date(utcTime)
        
        // Format as "HH:MMam/pm - Month DD, YYYY"
        const options = {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        }
        const timeStr = date.toLocaleTimeString('en-US', options).toLowerCase()
        
        const dateOptions = {
            month: 'long',
            day: 'numeric',
            year: 'numeric'
        }
        const dateStr = date.toLocaleDateString('en-US', dateOptions)
        
        this.el.textContent = `${timeStr} - ${dateStr}`
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