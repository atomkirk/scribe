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

Hooks.ScrollToBottom = {
    mounted() {
        this.scrollToBottom()
        // Watch for updates
        this.handleEvent("scroll-to-bottom", () => {
            this.scrollToBottom()
        })
    },
    updated() {
        this.scrollToBottom()
    },
    scrollToBottom() {
        setTimeout(() => {
            this.el.scrollTop = this.el.scrollHeight
        }, 0)
    }
}

export default Hooks